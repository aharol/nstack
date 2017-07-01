{-# OPTIONS_GHC -fno-warn-orphans #-}

module NStack.Module.ConfigFile where

import Control.Monad
import Control.Monad.Except(MonadError)              -- mtl
import Control.Monad.Trans(MonadIO, liftIO)          -- mtl
import Data.Aeson.Types (typeMismatch)
import Data.Text(Text, unpack, pack)
import qualified Data.Yaml as Y
import Data.Yaml((.:), (.:?), (.!=))
import Data.String (IsString)
import Turtle ((</>))
import qualified Turtle as R

import NStack.Module.Types (ModuleName(..), Stack(..))
import NStack.Module.Parser (parseModuleName, pStack, inlineParser)
import NStack.Prelude.FilePath (fromFP, toFP)
import NStack.Prelude.Exception (throwPermanentError)
type API = Text
type Package = Text
type Command = Text
type File = Text
-- TODO - rename as Project?

-- | ConfigFile module configuration file
-- used to describe the module project dir
data ConfigFile = ConfigFile {
  _cfgName :: Maybe ModuleName,
  _cfgStack :: Stack,
  _cfgParent :: ModuleName,
  _cfgPackages :: [Package],
  _cfgCommands :: [Command],
  _cfgFiles :: [File]
} deriving (Show)

instance Y.FromJSON ConfigFile where
  parseJSON (Y.Object v) =
    ConfigFile <$>
    v .:? "name" <*>
    v .: "stack" <*>
    v .: "parent" <*>
    v .:? "packages" .!= mempty <*>
    v .:? "commands" .!= mempty <*>
    v .:? "files" .!= mempty
  parseJSON _ = mzero

instance Y.FromJSON ModuleName where
  parseJSON (Y.String t) = either fail return $ parseModuleName t
  parseJSON _ = mzero

instance Y.FromJSON Stack where
  parseJSON obj@(Y.String t) = either (`typeMismatch` obj) return (inlineParser pStack t)
  parseJSON _ = mzero

instance Y.ToJSON Stack where
  toJSON = Y.String . pack . show

configFile :: IsString s => s
configFile = "nstack.yaml"

workflowFile :: IsString s => s
workflowFile = "module.nml"

-- | Return the config for the module
getConfigFile :: (MonadIO m) => R.FilePath -> m ConfigFile
getConfigFile moduleDir =
  either (throwPermanentError . prettyPrintParseException) return =<<
    liftIO (Y.decodeFileEither $ fromFP (moduleDir </> configFile))

-- | Project File
projectFile :: IsString s => s
projectFile = "nstack-project.yaml"

data ProjectFile = ProjectFile {
  _projectModules :: [R.FilePath]
} deriving (Show)

instance Y.FromJSON ProjectFile where
  parseJSON (Y.Object v) =
    ProjectFile <$>
    v .: "modules"
  parseJSON _ = mzero

instance Y.FromJSON R.FilePath where
  parseJSON (Y.String t) = return.toFP.unpack $ t
  parseJSON _ = mzero

-- | Return the project file in the current dir
getProjectFile :: (MonadIO m, MonadError String m) => m ProjectFile
getProjectFile =
  either (throwPermanentError . prettyPrintParseException) return =<<
    liftIO (Y.decodeFileEither $ fromFP projectFile)

prettyPrintParseException :: Y.ParseException -> String
prettyPrintParseException e =
  case e of
    -- Y.prettyPrintParseException adds 'Aeson exception: ' to the
    -- error message, which is completely unhelpful
    Y.AesonException s -> s
    _ -> Y.prettyPrintParseException e
