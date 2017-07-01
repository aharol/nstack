module NStack.Prelude.Applicative (tuple, (<&>), afold, guarded) where

import Control.Applicative

-- TODO - rename to NStack.Prelude.FAM ?

tuple :: Applicative f => f a -> f b -> f (a, b)
tuple a b = liftA2 (,) a b

-- this exists in lens, but copied into here to not depend on lens
(<&>) :: Functor f => f a -> (a -> b) -> f b
(<&>) = flip fmap
infixl 1 <&>

afold :: (Foldable f, Alternative g) => f a -> g a
afold = foldr ((<|>) . pure) empty

guarded :: Alternative f => (a -> Bool) -> a -> f a
guarded p a = case p a of
               True -> pure a
               False -> empty
