{-# OPTIONS_GHC -Wall -fwarn-tabs #-}
{-# LANGUAGE CPP
           , MultiParamTypeClasses
           , FlexibleContexts
           #-}

----------------------------------------------------------------
--                                                  ~ 2021.12.12
-- |
-- Module      :  test/PropertyTests
-- Copyright   :  2008--2021 wren gayle romano
-- License     :  BSD3
-- Maintainer  :  wren@cpan.org
-- Stability   :  provisional
-- Portability :  semi-portable (MPTC,...)
--
-- Property testing 'Trie's.
----------------------------------------------------------------
module PropertyTests (smallcheckTests, quickcheckTests) where

import Utils

import qualified Data.Trie              as T
import qualified Data.Trie.Internal     as TI
import qualified Data.Trie.Convenience  as TC
import qualified Data.ByteString        as S

import qualified Test.Tasty             as Tasty
import qualified Test.Tasty.SmallCheck  as SC
import qualified Test.Tasty.QuickCheck  as QC

import Data.List (nubBy, sortBy)
import Data.Ord  (comparing)
import qualified Data.Foldable as F

#if MIN_VERSION_base(4,13,0)
-- [aka GHC 8.8.1]: Prelude re-exports 'Semigroup'.
#elif MIN_VERSION_base(4,9,0)
-- [aka GHC 8.0.1]: "Data.Semigroup" added to base.
import Data.Semigroup      (Semigroup(..))
#elif MIN_VERSION_base(4,5,0)
-- [aka GHC 7.4.1]: @(<>)@ added to "Data.Monoid".
import Data.Monoid         ((<>))
#endif

#if MIN_VERSION_base(4,9,0)
import Data.Semigroup      (Sum(..))
#else
data Sum a = Sum a
    deriving (Eq, Ord, Read, Show, Bounded, Num)
instance Num a => Monoid (Sum a) where
    mempty = Sum 0
    mappend (Sum x) (Sum y) = Sum (x + y)
#endif

----------------------------------------------------------------
----------------------------------------------------------------
{-
TODO: see if we can't figure out some way of wrapping our properties
so that we can just write this list once and then pass in a token
for which checker to resolve to; something like:

    data Prop a = Prop String a

    data PropChecker = QuickCheck | SmallCheck
        deriving (Eq, Show)

    testProp :: (QC.Testable a, SC.Testable IO a) => PropChecker -> Prop a -> Tasty.TestTree
    testProp QuickCheck (Prop name a) = QC.testProperty name a
    testProp SmallCheck (Prop name a) = SC.testProperty name a

Of course, the problem with that implementation is that we need to
have the Prop remain polymorphic in the CheckGuard type, and have
testProp resolve it depending on the PropChecker.  So is there a way
to do that without GADTs or impredicativity?
-}

quickcheckTests :: Tasty.TestTree
quickcheckTests
  = Tasty.testGroup "QuickCheck"
  [ Tasty.testGroup "Data.Trie.ByteStringInternal"
    [ QC.testProperty
        "prop_breakMaximalPrefix"
        (prop_breakMaximalPrefix :: WS -> WS -> Bool)
    ]
  , Tasty.testGroup "Trivialities (@Int)"
    [ QC.testProperty
        "prop_singleton"
        (prop_singleton     :: WS -> Int -> Bool)
    , QC.testProperty
        "prop_insert_lookup"
        (prop_insert_lookup :: WS -> Int -> WTrie Int -> Bool)
    , QC.testProperty
        "prop_delete_lookup"
        (prop_delete_lookup :: WS -> WTrie Int -> Bool)
    , QC.testProperty
        "prop_insert_size"
        (prop_insert_size   :: WS -> Int -> WTrie Int -> Bool)
    , QC.testProperty
        "prop_delete_size"
        (prop_delete_size   :: WS -> WTrie Int -> Bool)
    , QC.testProperty
        "prop_insert_delete"
        (prop_insert_delete :: WS -> Int -> WTrie Int -> Bool)
    ]
  , Tasty.testGroup "Submap (@Int)"
    [ QC.testProperty
        "prop_submap_keysAreMembers"
        (prop_submap_keysAreMembers :: WS -> WTrie Int -> Bool)
    , QC.testProperty
        "prop_submap_keysHavePrefix"
        (prop_submap_keysHavePrefix :: WS -> WTrie Int -> Bool)
    , QC.testProperty
        "prop_submap_valuesEq"
        (prop_submap_valuesEq       :: WS -> WTrie Int -> Bool)
    , QC.testProperty
        "prop_deleteSubmap_keysAreMembers"
        (prop_deleteSubmap_keysAreMembers :: WS -> WTrie Int -> Bool)
    , QC.testProperty
        "prop_deleteSubmap_keysLackPrefix"
        (prop_deleteSubmap_keysLackPrefix :: WS -> WTrie Int -> Bool)
    , QC.testProperty
        "prop_deleteSubmap_disunion"
        (prop_deleteSubmap_disunion :: WS -> WTrie Int -> Bool)
    ]
  , Tasty.localOption (QC.QuickCheckMaxSize 300)
    -- BUG: fix that 'Tasty.localOption'
  $ Tasty.testGroup "Intersection (@Int)"
    [ QC.testProperty
        "prop_intersectL"
        (prop_intersectL    :: WTrie Int -> WTrie Int -> Bool)
    , QC.testProperty
        "prop_intersectR"
        (prop_intersectR    :: WTrie Int -> WTrie Int -> Bool)
    , QC.testProperty
        "prop_intersectPlus"
        (prop_intersectPlus :: WTrie Int -> WTrie Int -> Bool)
    ]
  , Tasty.testGroup "Matching (@Int)"
    [ QC.testProperty
        "prop_matches_keysOrdered"
        (prop_matches_keysOrdered   :: WS -> WTrie Int -> Bool)
    , QC.testProperty
        "prop_matches_keysArePrefix"
        (prop_matches_keysArePrefix :: WS -> WTrie Int -> Bool)
    , QC.testProperty
        "prop_minMatch_is_first_matches"
        (prop_minMatch_is_first_matches :: WS -> WTrie Int -> Bool)
    , QC.testProperty
        "prop_match_is_last_matches"
        (prop_match_is_last_matches :: WS -> WTrie Int -> Bool)
    ]
  , Tasty.testGroup "Priority-queue (@Int)"
    [ QC.testProperty
        "prop_minAssoc_is_first_toList"
        (prop_minAssoc_is_first_toList :: WTrie Int -> Bool)
    , QC.testProperty
        "prop_maxAssoc_is_last_toList"
        (prop_maxAssoc_is_last_toList :: WTrie Int -> Bool)
    , QC.testProperty
        "prop_updateMinViewBy_ident"
        (prop_updateMinViewBy_ident :: WTrie Int -> Bool)
    , QC.testProperty
        "prop_updateMaxViewBy_ident"
        (prop_updateMaxViewBy_ident :: WTrie Int -> Bool)
    , QC.testProperty
        "prop_updateMinViewBy_gives_minAssoc"
        (prop_updateMinViewBy_gives_minAssoc :: (WS -> Int -> Maybe Int) -> WTrie Int -> Bool)
    , QC.testProperty
        "prop_updateMaxViewBy_gives_maxAssoc"
        (prop_updateMaxViewBy_gives_maxAssoc :: (WS -> Int -> Maybe Int) -> WTrie Int -> Bool)
    ]
  , Tasty.testGroup "toList (@Int)"
    [ QC.testProperty
        "prop_toListBy_keysOrdered"
        (prop_toListBy_keysOrdered  :: WTrie Int -> Bool)
    , QC.testProperty
        "prop_keys"
        (prop_keys :: WTrie Int -> Bool)
    , QC.testProperty
        "prop_elems"
        (prop_elems :: WTrie Int -> Bool)
    ]
  , Tasty.testGroup "fromList (@Int)"
    [ QC.testProperty
        "prop_fromList_takes_first"
        (prop_fromList_takes_first  :: [(WS, Int)] -> Bool)
    , QC.testProperty
        "prop_fromListR_takes_first"
        (prop_fromListR_takes_first :: [(WS, Int)] -> Bool)
    , QC.testProperty
        "prop_fromListL_takes_first"
        (prop_fromListL_takes_first :: [(WS, Int)] -> Bool)
    , QC.testProperty
        "prop_fromListS_takes_first"
        (prop_fromListS_takes_first :: [(WS, Int)] -> Bool)
    , QC.testProperty
        "prop_fromListWithConst_takes_first"
        (prop_fromListWithConst_takes_first :: [(WS, Int)] -> Bool)
    , QC.testProperty
        "prop_fromListWithLConst_takes_first"
        (prop_fromListWithLConst_takes_first :: [(WS, Int)] -> Bool)
    ]
  , Tasty.testGroup "Type classes"
    [ Tasty.testGroup "Functor (@Int)"
      [ QC.testProperty
          "prop_FunctorIdentity"
          (prop_FunctorIdentity   :: WTrie Int -> Bool)
      -- TODO: prop_FunctorCompose
      {-
      -- TODO: still worth it to do this test with 'undefined'?
      , QC.testProperty
          "prop_fmap_keys"
          (prop_fmap_keys (undefined :: Int -> Int) :: WTrie Int -> Bool)
      -}
      , QC.testProperty
          -- TODO: generalize to other functions.
          "prop_fmap_toList"
          (prop_fmap_toList (+1) :: WTrie Int -> Bool)
      ]
    , Tasty.testGroup "Applicative (@Int)"
      [ QC.testProperty
          "prop_ApplicativeIdentity"
          (prop_ApplicativeIdentity :: WTrie Int -> Bool)
      -- TODO: prop_ApplicativeCompose, prop_ApplicativeHom, prop_ApplicativeInterchange
      ]
    , Tasty.testGroup "Monad (@Int)"
      [ QC.testProperty
          "prop_MonadIdentityR"
          (prop_MonadIdentityR :: WTrie Int -> Bool)
      -- TODO: prop_MonadIdentityL, prop_MonadAssoc
      ]
    , Tasty.testGroup "Foldable (@Int)"
      [ QC.testProperty
          "prop_foldr_vs_foldrWithKey"
          (prop_foldr_vs_foldrWithKey :: WTrie Int -> Bool)
#if MIN_VERSION_base(4,6,0)
      , QC.testProperty
          "prop_foldr_vs_foldr'"
          (prop_foldr_vs_foldr' :: WTrie Int -> Bool)
      , QC.testProperty
          "prop_foldl_vs_foldl'"
          (prop_foldl_vs_foldl' :: WTrie Int -> Bool)
#endif
#if MIN_VERSION_base(4,13,0)
      , QC.testProperty
          "prop_foldMap_vs_foldMap'"
          (prop_foldMap_vs_foldMap' :: WTrie Int -> Bool)
#endif
      ]
    -- TODO: Traversable
#if MIN_VERSION_base(4,9,0)
    , Tasty.testGroup "Semigroup (@Sum Int)"
      [ QC.testProperty
          -- This one is a bit more expensive: ~1sec instead of <=0.5sec
          "prop_Semigroup"
          (prop_Semigroup :: WTrie (Sum Int) -> WTrie (Sum Int) -> WTrie (Sum Int) -> Bool)
      ]
#endif
    , Tasty.testGroup "Monoid (@Sum Int)"
      [ QC.testProperty
          "prop_MonoidIdentityL"
          (prop_MonoidIdentityL :: WTrie (Sum Int) -> Bool)
      , QC.testProperty
          "prop_MonoidIdentityR"
          (prop_MonoidIdentityR :: WTrie (Sum Int) -> Bool)
      ]
    ]
  , Tasty.testGroup "Other mapping/filtering (@Int)"
    [ QC.testProperty
        "prop_filterMap_ident"
        (prop_filterMap_ident :: WTrie Int -> Bool)
    , QC.testProperty
        "prop_filterMap_empty"
        (prop_filterMap_empty :: WTrie Int -> Bool)
    , QC.testProperty
        "prop_mapBy_keys"
        (prop_mapBy_keys :: WTrie Int -> Bool)
    , QC.testProperty
        "prop_contextualMap_ident"
        (prop_contextualMap_ident :: WTrie Int -> Bool)
    , QC.testProperty
        "prop_contextualMap'_ident"
        (prop_contextualMap'_ident :: WTrie Int -> Bool)
    , QC.testProperty
        "prop_contextualFilterMap_ident"
        (prop_contextualFilterMap_ident :: WTrie Int -> Bool)
    , QC.testProperty
        "prop_contextualMapBy_keys"
        (prop_contextualMapBy_keys :: WTrie Int -> Bool)
    , QC.testProperty
        "prop_contextualMapBy_ident"
        (prop_contextualMapBy_ident :: WTrie Int -> Bool)
    , QC.testProperty
        "prop_contextualMapBy_empty"
        (prop_contextualMapBy_empty :: WTrie Int -> Bool)
    ]
  ]


----------------------------------------------------------------
adjustSmallCheckDepth
    :: (SC.SmallCheckDepth -> SC.SmallCheckDepth)
    -> Tasty.TestTree -> Tasty.TestTree
adjustSmallCheckDepth = Tasty.adjustOption

-- Throughout, we try to use 'W' or @()@ whenever we can, to reduce
-- the exponential growth problem.
smallcheckTests :: Tasty.TestTree
smallcheckTests
  = Tasty.testGroup "SmallCheck"
  [ Tasty.testGroup "Data.Trie.ByteStringInternal"
    [ adjustSmallCheckDepth (+1)
    $ SC.testProperty
        "prop_breakMaximalPrefix"
        (prop_breakMaximalPrefix :: WS -> WS -> Bool)
    ]
  , Tasty.testGroup "Trivialities (@W/@())"
    [ adjustSmallCheckDepth (+2)
    $ SC.testProperty
        -- This one can easily handle depth=6 fine (~0.1sec), but d=7 (~4sec)
        "prop_singleton"
        (prop_singleton     :: WS -> W -> Bool)
    , SC.testProperty
        -- Warning: depth 4 takes >10sec!
        "prop_insert_lookup"
        (prop_insert_lookup :: WS -> W -> WTrie W -> Bool)
    , SC.testProperty
        -- Don't waste any depth on the values!
        -- Warning: depth 4 takes >10sec!
        "prop_delete_lookup"
        (prop_delete_lookup :: WS -> WTrie () -> Bool)
    , SC.testProperty
        -- Don't waste any depth on the values!
        -- Warning: depth 4 takes >10sec!
        "prop_insert_size"
        (prop_insert_size   :: WS -> () -> WTrie () -> Bool)
    , SC.testProperty
        -- Don't waste any depth on the values!
        -- Warning: depth 4 takes >10sec!
        -- FIXME: at depth 3: 388/410 (94%) did not meet the condition!
        -- (That is, before rephrasing to avoid using 'CheckGuard')
        "prop_delete_size"
        (prop_delete_size   :: WS -> WTrie () -> Bool)
    , SC.testProperty
        -- Note: at depth 3: 136/2120 (6.4%) did not meet the condition.
        -- (That is, before rephrasing to avoid using 'CheckGuard')
        "prop_insert_delete"
        (prop_insert_delete :: WS -> W -> WTrie W -> Bool)
    ]
  , Tasty.testGroup "Submap (@()/@W)"
    -- Depth=4 is at best very marginal here...
    [ SC.testProperty
        "prop_submap_keysAreMembers"
        (prop_submap_keysAreMembers :: WS -> WTrie () -> Bool)
    , SC.testProperty
        "prop_submap_keysHavePrefix"
        (prop_submap_keysHavePrefix :: WS -> WTrie () -> Bool)
    , SC.testProperty
        "prop_submap_valuesEq"
        (prop_submap_valuesEq       :: WS -> WTrie W -> Bool)
    , SC.testProperty
        "prop_deleteSubmap_keysAreMembers"
        (prop_deleteSubmap_keysAreMembers :: WS -> WTrie () -> Bool)
    , SC.testProperty
        "prop_deleteSubmap_keysLackPrefix"
        (prop_deleteSubmap_keysLackPrefix :: WS -> WTrie () -> Bool)
    , SC.testProperty
        "prop_deleteSubmap_disunion"
        (prop_deleteSubmap_disunion :: WS -> WTrie W -> Bool)
    ]
  , Tasty.testGroup "Intersection (@W/@Int)"
    -- Warning: Using depth=4 here is bad (the first two take about
    -- 26.43sec; the last one much longer).
    [ SC.testProperty
        "prop_intersectL"
        (prop_intersectL    :: WTrie W -> WTrie W -> Bool)
    , SC.testProperty
        "prop_intersectR"
        (prop_intersectR    :: WTrie W -> WTrie W -> Bool)
    , SC.testProperty
        "prop_intersectPlus"
        (prop_intersectPlus :: WTrie Int -> WTrie Int -> Bool)
    ]
  , Tasty.testGroup "Matching (@()/@W)"
    [ SC.testProperty
        "prop_matches_keysOrdered"
        (prop_matches_keysOrdered   :: WS -> WTrie () -> Bool)
    , SC.testProperty
        "prop_matches_keysArePrefix"
        (prop_matches_keysArePrefix :: WS -> WTrie () -> Bool)
    , SC.testProperty
        "prop_minMatch_is_first_matches"
        (prop_minMatch_is_first_matches :: WS -> WTrie W -> Bool)
    , SC.testProperty
        "prop_match_is_last_matches"
        (prop_match_is_last_matches :: WS -> WTrie W -> Bool)
    ]
  , Tasty.testGroup "Priority-queue (@W)"
    -- Depth=4 takes about 1sec each
    [ SC.testProperty
        "prop_minAssoc_is_first_toList"
        (prop_minAssoc_is_first_toList :: WTrie W -> Bool)
    , SC.testProperty
        "prop_maxAssoc_is_last_toList"
        (prop_maxAssoc_is_last_toList :: WTrie W -> Bool)
    , SC.testProperty
        "prop_updateMinViewBy_ident"
        (prop_updateMinViewBy_ident :: WTrie W -> Bool)
    , SC.testProperty
        "prop_updateMaxViewBy_ident"
        (prop_updateMaxViewBy_ident :: WTrie W -> Bool)
    -- HACK: must explicitly pass functions for these two, else they're too slow
    , SC.testProperty
        "prop_updateMinViewBy_gives_minAssoc"
        (prop_updateMinViewBy_gives_minAssoc undefined :: WTrie W -> Bool)
    , SC.testProperty
        "prop_updateMaxViewBy_gives_maxAssoc"
        (prop_updateMaxViewBy_gives_maxAssoc undefined :: WTrie W -> Bool)
    ]
  , Tasty.testGroup "toList (@()/@W)"
    -- These can handle depth 4, but it takes >1sec (but still <5sec)
    [ SC.testProperty
        "prop_toListBy_keysOrdered"
        (prop_toListBy_keysOrdered  :: WTrie () -> Bool)
    , SC.testProperty
        "prop_keys"
        (prop_keys :: WTrie () -> Bool)
    , SC.testProperty
        "prop_elems"
        (prop_elems :: WTrie W -> Bool)
    -- TODO: move these into the section for 'Foldable', to agree with QC
    , SC.testProperty
        "prop_foldr_vs_foldrWithKey"
        (prop_foldr_vs_foldrWithKey :: WTrie W -> Bool)
#if MIN_VERSION_base(4,6,0)
    , SC.testProperty
        "prop_foldr_vs_foldr'"
        (prop_foldr_vs_foldr' :: WTrie W -> Bool)
    , SC.testProperty
        "prop_foldl_vs_foldl'"
        (prop_foldl_vs_foldl' :: WTrie W -> Bool)
#endif
    -- TODO: prop_foldMap_vs_foldMap' requires (Num W) if we want to use W.
    ]
  , Tasty.adjustOption (+ (1::SC.SmallCheckDepth))
  $ Tasty.testGroup "fromList (@()/@W)"
    [ SC.testProperty
        "prop_fromList_takes_first"
        (prop_fromList_takes_first  :: [(WS, W)] -> Bool)
    , SC.testProperty
        "prop_fromListR_takes_first"
        (prop_fromListR_takes_first :: [(WS, W)] -> Bool)
    , SC.testProperty
        "prop_fromListL_takes_first"
        (prop_fromListL_takes_first :: [(WS, W)] -> Bool)
    , SC.testProperty
        "prop_fromListS_takes_first"
        (prop_fromListS_takes_first :: [(WS, W)] -> Bool)
    , SC.testProperty
        "prop_fromListWithConst_takes_first"
        (prop_fromListWithConst_takes_first :: [(WS, W)] -> Bool)
    , SC.testProperty
        "prop_fromListWithLConst_takes_first"
        (prop_fromListWithLConst_takes_first :: [(WS, W)] -> Bool)
    ]
  -- TODO: do we want to smallcheck any of the "Type classes" or "Other mapping/filtering" stuff we do in quickcheck?
  ]


----------------------------------------------------------------
----------------------------------------------------------------

-- | 'TI.breakMaximalPrefix' satisfies the documented equalities.
prop_breakMaximalPrefix :: WS -> WS -> Bool
prop_breakMaximalPrefix (WS s) (WS z) =
    let (pre,s',z') = TI.breakMaximalPrefix s z
    in (pre <> s') == s
    && (pre <> z') == z

{-
-- FIXME: need to export the RLBS stuff if we are to test it...
prop_toStrict :: [WS] -> Bool
prop_toStrict =
    (S.concat .==. (TI.toStrict . foldl' (+>) Epsilon)) . map unWS
-}

----------------------------------------------------------------
-- | A singleton, is.
prop_singleton :: (Eq a) => WS -> a -> Bool
prop_singleton (WS k) v =
    T.singleton k v == T.insert k v T.empty

-- | If you insert a value, you can look it up.
prop_insert_lookup :: (Eq a) => WS -> a -> WTrie a -> Bool
prop_insert_lookup (WS k) v (WT t) =
    (T.lookup k . T.insert k v $ t) == Just v

-- | If you delete a value, you can't look it up.
prop_delete_lookup :: WS -> WTrie a -> Bool
prop_delete_lookup (WS k) =
    isNothing . T.lookup k . T.delete k . unWT
    where
    isNothing Nothing  = True
    isNothing (Just _) = False

-- TODO: print/record diagnostics re what proportion of calls have
-- @n=0@ vs @n=1@, to ensure proper coverage.
prop_insert_size :: WS -> a -> WTrie a -> Bool
prop_insert_size (WS k) v (WT t) =
    ((T.size . T.insert k v) .==. ((n +) . T.size)) $ t
    where
    n = if T.member k t then 0 else 1

-- TODO: print/record diagnostics re what proportion of calls have
-- @n=0@ vs @n=1@, to ensure proper coverage.
prop_delete_size :: WS -> WTrie a -> Bool
prop_delete_size (WS k) (WT t) =
    ((T.size . T.delete k) .==. (subtract n . T.size)) $ t
    where
    n = if T.member k t then 1 else 0

prop_insert_delete :: (Eq a) => WS -> a -> WTrie a -> Bool
prop_insert_delete (WS k) v (WT t)
    | T.member k t = ((T.delete k . T.insert k v) .==. T.delete k) $ t
    | otherwise    = ((T.delete k . T.insert k v) .==. id)         $ t

-- | All keys in a submap are keys in the supermap
prop_submap_keysAreMembers :: WS -> WTrie a -> Bool
prop_submap_keysAreMembers (WS q) (WT t) =
    all (`T.member` t) . T.keys . T.submap q $ t
    -- TODO: should we use 'QC.conjoin' (assuming another class to overload it) in lieu of 'all'? What are the actual benefits of doing so? Ditto for all the uses below.

-- | All keys in a submap have the query as a prefix
prop_submap_keysHavePrefix :: WS -> WTrie a -> Bool
prop_submap_keysHavePrefix (WS q) =
    all (q `S.isPrefixOf`) . T.keys . T.submap q . unWT

-- | All values in a submap are the same in the supermap
prop_submap_valuesEq :: (Eq a) => WS -> WTrie a -> Bool
prop_submap_valuesEq (WS q) (WT t) =
    ((`T.lookup` t') .==. (`T.lookup` t)) `all` T.keys t'
    where t' = T.submap q t

-- | All keys in the result are keys in the supermap
prop_deleteSubmap_keysAreMembers :: WS -> WTrie a -> Bool
prop_deleteSubmap_keysAreMembers (WS q) (WT t) =
    all (`T.member` t) . T.keys . T.deleteSubmap q $ t

-- | All keys in a submap lack the query as a prefix
prop_deleteSubmap_keysLackPrefix :: WS -> WTrie a -> Bool
prop_deleteSubmap_keysLackPrefix (WS q) =
    all (not . S.isPrefixOf q) . T.keys . T.deleteSubmap q . unWT

-- | `T.submap` and `T.deleteSubmap` partition every trie for every key.
prop_deleteSubmap_disunion :: (Eq a) => WS -> WTrie a -> Bool
prop_deleteSubmap_disunion (WS q) (WT t) =
    t == (T.submap q t `TC.disunion` T.deleteSubmap q t)

-- TODO: other than as a helper like below, could we actually
-- generate interesting enough functions to make this worth testing
-- directly?
--
-- | Arbitrary @x ∩ y == (x ∪ y) ⋈ (x ⋈ y)@.
prop_intersectBy :: (Eq a) => (a -> a -> Maybe a) -> WTrie a -> WTrie a -> Bool
prop_intersectBy f (WT x) (WT y) =
    T.intersectBy f x y == (T.mergeBy f x y `TC.disunion` TC.disunion x y)

-- | Left-biased @x ∩ y == (x ∪ y) ⋈ (x ⋈ y)@.
prop_intersectL :: (Eq a) => WTrie a -> WTrie a -> Bool
prop_intersectL = prop_intersectBy (\x _ -> Just x)

-- | Right-biased @x ∩ y == (x ∪ y) ⋈ (x ⋈ y)@.
prop_intersectR :: (Eq a) => WTrie a -> WTrie a -> Bool
prop_intersectR = prop_intersectBy (\_ y -> Just y)

-- | Additive @x ∩ y == (x ∪ y) ⋈ (x ⋈ y)@.
prop_intersectPlus :: (Eq a, Num a) => WTrie a -> WTrie a -> Bool
prop_intersectPlus = prop_intersectBy (\x y -> Just (x + y))

isOrdered :: (Ord a) => [a] -> Bool
isOrdered xs = and (zipWith (<=) xs (drop 1 xs))

-- | 'T.toListBy', 'T.toList', and 'T.keys' are ordered by keys.
prop_toListBy_keysOrdered :: WTrie a -> Bool
prop_toListBy_keysOrdered = isOrdered . T.keys . unWT

fst3 :: (a,b,c) -> a
fst3 (a,_,_) = a

-- | 'T.matches' is ordered by keys.
prop_matches_keysOrdered :: WS -> WTrie a -> Bool
prop_matches_keysOrdered (WS q) (WT t) =
    isOrdered . map fst3 $ T.matches t q

-- | Matching keys are a prefix of the query.
prop_matches_keysArePrefix :: WS -> WTrie a -> Bool
prop_matches_keysArePrefix (WS q) (WT t) =
    all (`S.isPrefixOf` q) . map fst3 $ T.matches t q

_eqHead :: (Eq a) => Maybe a -> [a] -> Bool
_eqHead Nothing  []    = True
_eqHead (Just x) (y:_) = x == y
_eqHead _        _     = False

_eqLast :: (Eq a) => Maybe a -> [a] -> Bool
_eqLast Nothing  []       = True
_eqLast (Just x) ys@(_:_) = x == last ys
_eqLast _        _        = False

prop_minMatch_is_first_matches :: Eq a => WS -> WTrie a -> Bool
prop_minMatch_is_first_matches (WS q) (WT t) =
    _eqHead (T.minMatch t q) (T.matches t q)

prop_match_is_last_matches :: Eq a => WS -> WTrie a -> Bool
prop_match_is_last_matches (WS q) (WT t) =
    _eqLast (T.match t q) (T.matches t q)

prop_minAssoc_is_first_toList :: Eq a => WTrie a -> Bool
prop_minAssoc_is_first_toList (WT t) =
    _eqHead (TI.minAssoc t) (T.toList t)

prop_maxAssoc_is_last_toList :: Eq a => WTrie a -> Bool
prop_maxAssoc_is_last_toList (WT t) =
    _eqLast (TI.maxAssoc t) (T.toList t)

view2assoc :: Maybe (S.ByteString, a, T.Trie a) -> Maybe (S.ByteString, a)
view2assoc Nothing        = Nothing
view2assoc (Just (k,v,_)) = Just (k,v)

-- TODO: again, can we actually generate any interesting functions here?
prop_updateMinViewBy_gives_minAssoc :: Eq a => (WS -> a -> Maybe a) -> WTrie a -> Bool
prop_updateMinViewBy_gives_minAssoc f =
    ((view2assoc . TI.updateMinViewBy (f . WS)) .==. TI.minAssoc) . unWT

prop_updateMaxViewBy_gives_maxAssoc :: Eq a => (WS -> a -> Maybe a) -> WTrie a -> Bool
prop_updateMaxViewBy_gives_maxAssoc f =
    ((view2assoc . TI.updateMaxViewBy (f . WS)) .==. TI.maxAssoc) . unWT

view2trie :: Maybe (S.ByteString, a, T.Trie a) -> T.Trie a
view2trie Nothing        = T.empty
view2trie (Just (_,_,t)) = t

prop_updateMinViewBy_ident :: Eq a => WTrie a -> Bool
prop_updateMinViewBy_ident =
    ((view2trie . TI.updateMinViewBy (\_ v -> Just v)) .==. id) . unWT

prop_updateMaxViewBy_ident :: Eq a => WTrie a -> Bool
prop_updateMaxViewBy_ident =
    ((view2trie . TI.updateMaxViewBy (\_ v -> Just v)) .==. id) . unWT

prop_keys :: WTrie a -> Bool
prop_keys = (T.keys .==. (fmap fst . T.toList)) . unWT

prop_elems :: (Eq a) => WTrie a -> Bool
prop_elems = (T.elems .==. (fmap snd . T.toList)) . unWT

-- Make sure these at least have the same order...
prop_foldr_vs_foldrWithKey :: Eq a => WTrie a -> Bool
prop_foldr_vs_foldrWithKey =
    (F.foldr (:) [] .==. TI.foldrWithKey (\_ v vs -> v:vs) []) . unWT

#if MIN_VERSION_base(4,6,0)
prop_foldr_vs_foldr' :: (Eq a) => WTrie a -> Bool
prop_foldr_vs_foldr' = (F.foldr (:) [] .==. F.foldr' (:) []) . unWT

prop_foldl_vs_foldl' :: (Eq a) => WTrie a -> Bool
prop_foldl_vs_foldl' = (F.foldl snoc [] .==. F.foldl' snoc []) . unWT
    where
    snoc = flip (:)
#endif

#if MIN_VERSION_base(4,13,0)
-- TODO: use a non-commutative Monoid, to ensure the order is the same.
prop_foldMap_vs_foldMap' ::  (Num a, Eq a) => WTrie a -> Bool
prop_foldMap_vs_foldMap' = (F.foldMap Sum .==. F.foldMap' Sum) . unWT
#endif

-- TODO: how can we best test that fold{l,r,Map}{,'} are sufficiently lazy\/strict?
-- See: <https://github.com/haskell/containers/blob/master/containers-tests/tests/intmap-strictness.hs>

-- TODO: #if MIN_VERSION_base(4,8,0), check that 'F.null' isn't cyclic definition

-- | If there are duplicate keys in the @assocs@, then @f@ will
-- take the first value.
_takes_first :: (Eq c) => ([(S.ByteString, c)] -> T.Trie c) -> [(WS, c)] -> Bool
_takes_first f assocs =
    (T.toList . f) .==. (nubBy (apFst (==)) . sortBy (comparing fst))
    $ map (first unWS) assocs

-- | Lift a function to apply to the 'fst' of pairs, retaining the 'snd'.
first :: (a -> b) -> (a,c) -> (b,c)
first f (x,y) = (f x, y)

-- | Lift a function to apply to the 'snd' of pairs, retaining the 'fst'.
second :: (b -> c) -> (a,b) -> (a,c)
second f (x,y) = (x, f y)

-- | Lift a binary function to apply to the first of pairs, discarding seconds.
apFst :: (a -> b -> c) -> ((a,d) -> (b,e) -> c)
apFst f (x,_) (y,_) = f x y

-- | 'T.fromList' takes the first value for a given key.
prop_fromList_takes_first :: (Eq a) => [(WS, a)] -> Bool
prop_fromList_takes_first = _takes_first T.fromList

-- | 'T.fromListR' takes the first value for a given key.
prop_fromListR_takes_first :: (Eq a) => [(WS, a)] -> Bool
prop_fromListR_takes_first = _takes_first TC.fromListR

-- | 'T.fromListL' takes the first value for a given key.
prop_fromListL_takes_first :: (Eq a) => [(WS, a)] -> Bool
prop_fromListL_takes_first = _takes_first TC.fromListL

-- | 'T.fromListS' takes the first value for a given key.
prop_fromListS_takes_first :: (Eq a) => [(WS, a)] -> Bool
prop_fromListS_takes_first = _takes_first TC.fromListS

-- | @('TC.fromListWith' const)@ takes the first value for a given key.
prop_fromListWithConst_takes_first :: (Eq a) => [(WS, a)] -> Bool
prop_fromListWithConst_takes_first = _takes_first (TC.fromListWith const)

-- | @('TC.fromListWithL' const)@ takes the first value for a given key.
prop_fromListWithLConst_takes_first :: (Eq a) => [(WS, a)] -> Bool
prop_fromListWithLConst_takes_first = _takes_first (TC.fromListWithL const)

prop_FunctorIdentity :: Eq a => WTrie a -> Bool
prop_FunctorIdentity = (fmap id .==. id) . unWT

{- -- TODO: is there any way to make this remotely testable?
prop_FunctorCompose :: Eq c => (b -> c) -> (a -> b) -> WTrie a -> Bool
prop_FunctorCompose f g = (fmap (f . g) .==. (fmap f . fmap g)) . unWT
-}

{-
-- Both of these test only a subset of what 'prop_fmap_toList' tests.  I was hoping they'd help simplify the function-generation problem, but if we're testing 'prop_fmap_toList' anyways then there's no point in testing these too.

-- | 'fmap' doesn't affect the keys. This is safe to call with an
-- undefined function, thereby proving that the function cannot
-- affect things.
prop_fmap_keys :: Eq b => (a -> b) -> WTrie a -> Bool
prop_fmap_keys f = ((T.keys . fmap f) .==. T.keys) . unWT

prop_fmap_elems :: Eq b => (a -> b) -> WTrie a -> Bool
prop_fmap_elems f = ((T.elems . fmap f) .==. (map f . T.elems)) . unWT
-}

-- TODO: is there any way to generate halfway useful functions for testing here?
prop_fmap_toList :: Eq b => (a -> b) -> WTrie a -> Bool
prop_fmap_toList f =
    ((T.toList . fmap f) .==. (map (second f) . T.toList)) . unWT

prop_filterMap_ident :: Eq a => WTrie a -> Bool
prop_filterMap_ident = (T.filterMap Just .==. id) . unWT

prop_filterMap_empty :: Eq a => WTrie a -> Bool
prop_filterMap_empty = (T.filterMap const_Nothing .==. const T.empty) . unWT
    where
    -- Have to fix the result type here.
    const_Nothing :: a -> Maybe a
    const_Nothing = const Nothing

justConst :: a -> b -> Maybe a
justConst x _ = Just x

prop_mapBy_keys :: WTrie a -> Bool
prop_mapBy_keys = all (uncurry (==)) . T.toList . T.mapBy justConst . unWT

prop_contextualMap_ident :: Eq a => WTrie a -> Bool
prop_contextualMap_ident = (TI.contextualMap const .==. id) . unWT

prop_contextualMap'_ident :: Eq a => WTrie a -> Bool
prop_contextualMap'_ident = (TI.contextualMap' const .==. id) . unWT

prop_contextualFilterMap_ident :: Eq a => WTrie a -> Bool
prop_contextualFilterMap_ident =
    (TI.contextualFilterMap justConst .==. id) . unWT

prop_contextualMapBy_keys :: WTrie a -> Bool
prop_contextualMapBy_keys =
    all (uncurry (==)) . T.toList . TI.contextualMapBy f . unWT
    where
    f k _ _ = Just k

prop_contextualMapBy_ident :: Eq a => WTrie a -> Bool
prop_contextualMapBy_ident = (TI.contextualMapBy f .==. id) . unWT
    where
    f _ v _ = Just v

prop_contextualMapBy_empty :: Eq a => WTrie a -> Bool
prop_contextualMapBy_empty = (TI.contextualMapBy f .==. const T.empty) . unWT
    where
    -- Have to fix the result type here.
    f :: S.ByteString -> a -> T.Trie a -> Maybe a
    f _ _ _ = Nothing

prop_ApplicativeIdentity :: Eq a => WTrie a -> Bool
prop_ApplicativeIdentity = ((pure id <*>) .==. id) . unWT

{- -- (remaining, untestable) Applicative laws
prop_ApplicativeCompose  = pure (.) <*> u <*> v <*> w == u <*> (v <*> w)
prop_ApplicativeHom      = pure f <*> pure x == pure (f x)
prop_ApplicativeInterchange = u <*> pure y == pure ($ y) <*> u
-}

prop_MonadIdentityR :: Eq a => WTrie a -> Bool
prop_MonadIdentityR = ((>>= return) .==. id) . unWT

{- -- (remaining, untestable) Monad laws
prop_MonadIdentityL = (return a >>= k) == k a
prop_MonadAssoc     = m >>= (\x -> k x >>= h) == (m >>= k) >>= h
-}

#if MIN_VERSION_base(4,9,0)
prop_Semigroup :: (Semigroup a, Eq a) => WTrie a -> WTrie a -> WTrie a -> Bool
prop_Semigroup (WT a) (WT b) (WT c) = a <> (b <> c) == (a <> b) <> c
#endif

-- N.B., base-4.11.0.0 is when Semigroup became superclass of Monoid
prop_MonoidIdentityL :: (Monoid a, Eq a) => WTrie a -> Bool
prop_MonoidIdentityL = ((mempty `mappend`) .==. id) . unWT

prop_MonoidIdentityR :: (Monoid a, Eq a) => WTrie a -> Bool
prop_MonoidIdentityR = ((`mappend` mempty) .==. id) . unWT

----------------------------------------------------------------
----------------------------------------------------------- fin.
