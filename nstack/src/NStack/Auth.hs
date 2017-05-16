module NStack.Auth where

import Control.Applicative (empty)
import Control.Lens (Prism', prism', (^.), (^?), re)
import Control.Monad ((>=>), mfilter)
import Crypto.Hash (Digest, digestFromByteString, hash)
import Crypto.Hash.Algorithms (SHA256)
import Crypto.MAC.HMAC (hmac, HMAC, hmacGetDigest)
import Data.Aeson
import Data.Aeson.Types (Parser)
import Data.ByteArray (ByteArrayAccess, ByteArray, convert)
import Data.ByteArray.Encoding (convertFromBase, convertToBase, Base(Base16))
import Data.ByteString (ByteString)
import Data.Either.Combinators (rightToMaybe)
import Data.Monoid ((<>))
import Data.SafeCopy (SafeCopy)
import Data.Serialize (Serialize, put, get, Putter, Get)
import Data.String (IsString)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Text.Encoding (encodeUtf8, decodeUtf8)
import GHC.Generics (Generic)
import Data.Data (Typeable, Data)
import GHC.Prim (coerce)

import NStack.Prelude.Applicative (afold)
import NStack.Prelude.Text (getText, putText)

type Signature = Digest SHA256
type Payload = ByteString

newtype UserName = UserName { _username :: Text }
  deriving (Eq, Ord, Generic, IsString, Typeable, Data)

instance Show UserName where
  show = coerce (show :: Text -> String)

nstackUserName :: UserName
nstackUserName = UserName "nstack"

instance SafeCopy UserName

instance FromJSON UserName where
  parseJSON a = coerce (parseJSON a :: Parser Text)

newtype UserId = UserId { _userId :: ByteString }
  deriving (Eq, Ord, Show, IsString, Generic)

instance SafeCopy UserId

hexUserId :: Prism' Text UserId
hexUserId = prism' (toBase16 . _userId) ((UserId <$>) . fromBase16)

newtype Email = Email { _email :: Text }
  deriving (Eq, Ord, Show, Generic, IsString)

-- NOTE - don't think it's worth doing any more complex validation here
validEmail :: Prism' Text Email
validEmail = prism' _email (\x -> Email <$> mfilter (T.any (== '@')) (Just x))

instance FromJSON Email where
  parseJSON a = coerce (parseJSON a :: Parser Text)

formatUserId :: UserId -> Text
formatUserId (UserId u) = toBase16 u

readUserId :: Text -> Maybe UserId
readUserId t = UserId <$> fromBase16 t

instance FromJSON UserId where
  parseJSON (String k) = afold $ k ^? hexUserId
  parseJSON _ = empty

instance ToJSON UserId where
  toJSON u = String $ u ^. re hexUserId

newtype SecretKey = SecretKey ByteString
  deriving (Eq, Show, IsString)

formatKey :: SecretKey -> Text
formatKey (SecretKey k) = toBase16 k

readKey :: Text -> Maybe SecretKey
readKey t = SecretKey <$> fromBase16 t

textSecretKey :: Prism' Text SecretKey
textSecretKey = prism' formatKey readKey

instance FromJSON SecretKey where
  parseJSON (String k) = maybe empty (pure . SecretKey) $ fromBase16 k
  parseJSON _ = empty

instance ToJSON SecretKey where
  toJSON (SecretKey k) = String $ toBase16 k

-- The first field is the HMAC of the second field
-- The second field is the SHA256 hash of the payload
data SignedPayloadHash = SignedPayloadHash Signature Signature
  deriving Show

data Credentials = Credentials UserId SignedPayloadHash
  deriving Show

data AuthedUser = AuthedUser UserId UserName Email
  deriving Generic

instance Serialize AuthedUser where

instance Serialize UserId where
  put = coerce (put :: Putter ByteString)
  get = coerce (get :: Get ByteString)

instance Serialize UserName where
  put = coerce putText
  get = coerce getText

instance Serialize Email where
  put = coerce putText
  get = coerce getText

data Unauthenticated = Unauthenticated

validateCredentials :: Monad m => (UserId -> m (Maybe SecretKey)) -> Credentials -> m Bool
validateCredentials lookupF (Credentials user (SignedPayloadHash sig payload)) = do
  key <- lookupF user
  return $ maybe False (\k -> sig == reconstruct k payload) key

reconstruct :: SecretKey -> Digest SHA256 -> Signature
reconstruct k payload = hmacGetDigest $ hmacSha256 k (convert payload)

hmacSha256 :: SecretKey -> Payload -> HMAC SHA256
hmacSha256 (SecretKey k) p = hmac k p

digestFromBase16 :: Text -> Maybe Signature
digestFromBase16 = (fromBase16 :: Text -> Maybe ByteString) >=> digestFromByteString

fromBase16 :: ByteArray b => Text -> Maybe b
fromBase16 = rightToMaybe . convertFromBase Base16 . encodeUtf8

toBase16 :: ByteArrayAccess b => b -> Text
toBase16 = decodeUtf8 . convertToBase Base16

{-
   Class to get the payload from a request to be signed.
   Abstracts over different request implementations (E.g. wai vs http-client)
   Instances implement the individual getters, whilst `getPayload` ensures we
   check the same fields
   -}

sign :: (Applicative m, GetPayload a m) => SecretKey -> a -> m Text
sign k a = toBase16 . reconstruct k . hash <$> getPayload a

getPayload :: (Applicative m, GetPayload a m) => a -> m ByteString
getPayload a = (<>) <$> getPath a <*> getBody a

-- TODO: We should be signing a timestamp too, so we can limit validity of requests
-- and restrict replay attacks
class GetPayload a m | a -> m where
  getPath :: a -> m ByteString
  getBody :: a -> m ByteString
