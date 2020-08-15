{-# LANGUAGE OverloadedStrings #-}

module ClickHouseDriver.Core.Column where

import ClickHouseDriver.IO.BufferedReader
import ClickHouseDriver.IO.BufferedWriter
import Control.Monad.State.Lazy
import Data.Binary
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as C8
import Data.ByteString (ByteString, isPrefixOf)
import Data.ByteString.Builder
import Data.ByteString.Char8 (readInt)
import Data.Int
import Data.Traversable
import Data.Vector (Vector, (!))
import qualified Data.Vector as V
import Data.Word
import qualified Data.List as List
import qualified Data.Map as Map
import Data.Time (Day, addDays, fromGregorian, toGregorian)
--Debug 
import Debug.Trace 

data ClickhouseType
  = CKBool Bool
  | CKInt8 Int8
  | CKInt16 Int16
  | CKInt32 Int32
  | CKInt64 Int64
  | CKUInt8 Word8
  | CKUInt16 Word16
  | CKUInt32 Word32
  | CKUInt64 Word64
  | CKString ByteString
  | CKFixedLengthString Int ByteString
  | CKTuple (Vector ClickhouseType)
  | CKArray (Vector ClickhouseType)
  | CKDecimal32 Float
  | CKDecimal64 Float
  | CKDecimal128 Float
  | CKDateTime
  | CKDate {
    year :: !Integer,
    month :: !Int,
    day :: !Int 
  }
  | CKNull
  deriving (Show, Eq)

readStatePrefix :: Reader Word64
readStatePrefix = readBinaryUInt64

readNull :: Reader Word8
readNull = readBinaryUInt8

getColumnWithSpec ::  Int -> ByteString -> Reader (Vector ClickhouseType)
getColumnWithSpec n_rows spec
  | "String" `isPrefixOf` spec = V.replicateM n_rows (CKString <$> readBinaryStr)
  | "Array" `isPrefixOf` spec = readArray n_rows spec
  | "FixedString" `isPrefixOf` spec = readFixed n_rows spec
  | "DateTime" `isPrefixOf` spec = undefined --TODO
  | "Date"     `isPrefixOf` spec = readDate n_rows spec
  | "Tuple" `isPrefixOf` spec = readTuple n_rows spec
  | "Nullable" `isPrefixOf` spec = readNullable n_rows spec
  | "LowCardinality" `isPrefixOf` spec = undefined--TODO
  | "Decimal" `isPrefixOf` spec = readDecimal n_rows spec
  | "SimpleAggregateFunction" `isPrefixOf` spec = undefined--TODO
  | "Enum" `isPrefixOf` spec = readEnum n_rows spec
  | "Int" `isPrefixOf` spec = readIntColumn n_rows spec
  | "UInt" `isPrefixOf` spec = readIntColumn n_rows spec
  | otherwise = error ("Unknown Type: " Prelude.++ C8.unpack spec)

readIntColumn ::  Int -> ByteString -> Reader (Vector ClickhouseType)
readIntColumn n_rows "Int8" = V.replicateM n_rows (CKInt8 <$> readBinaryInt8)
readIntColumn n_rows "Int16" = V.replicateM n_rows (CKInt16 <$> readBinaryInt16)
readIntColumn n_rows "Int32" = V.replicateM n_rows (CKInt32 <$> readBinaryInt32)
readIntColumn n_rows "Int64" = V.replicateM n_rows (CKInt64 <$> readBinaryInt64)
readIntColumn n_rows "UInt8" = V.replicateM n_rows (CKUInt8 <$> readBinaryUInt8)
readIntColumn n_rows "UInt16" = V.replicateM n_rows (CKUInt16 <$> readBinaryUInt16)
readIntColumn n_rows "UInt32" = V.replicateM n_rows (CKUInt32 <$> readBinaryUInt32)
readIntColumn n_rows "UInt64" = V.replicateM n_rows (CKUInt64 <$> readBinaryUInt64)
readIntColumn _ _ = error "Not an integer type"

readFixed :: Int -> ByteString -> Reader (Vector ClickhouseType)
readFixed n_rows spec = do
  let l = BS.length spec
  let strnumber = BS.take (l - 13) (BS.drop 12 spec)
  let number = case readInt strnumber of
        Nothing -> 0 -- This can't happen
        Just (x, _) -> x
  result <- V.replicateM n_rows (readFixedLengthString number)
  return result

readFixedLengthString :: Int -> Reader ClickhouseType
readFixedLengthString strlen = (CKFixedLengthString strlen) <$> (readBinaryStrWithLength strlen)

readDateTime ::  Int -> ByteString -> Reader (Vector ClickhouseType)
readDateTime n_rows spec
          | "DateTime64" `isPrefixOf` spec = undefined
          |  otherwise = undefined 

{-
          Informal description for this config:
          (\Null | \SOH)^{n_rows}
-}
readNullable :: Int->ByteString->Reader (Vector ClickhouseType)
readNullable n_rows spec = do
    let l = BS.length spec
    let cktype = BS.take (l - 10) (BS.drop 9 spec) -- Read Clickhouse type inside the bracket after the 'Nullable' spec.
    config <- readNullableConfig n_rows spec
    items <- getColumnWithSpec n_rows cktype
    let result = V.generate n_rows (\i->if config ! i == 1 then CKNull else items ! i)
    return result
      where
        readNullableConfig :: Int->ByteString->Reader (Vector Word8)
        readNullableConfig n_rows spec = do
          config <- readBinaryStrWithLength n_rows
          (return . V.fromList . BS.unpack) config

{-
  Format:
  "
     One element of array of arrays can be represented as tree:
      (0 depth)          [[3, 4], [5, 6]]
                        |               |
      (1 depth)      [3, 4]           [5, 6]
                    |    |           |    |
      (leaf)        3     4          5     6
      Offsets (sizes) written in breadth-first search order. In example above
      following sequence of offset will be written: 4 -> 2 -> 4
      1) size of whole array: 4
      2) size of array 1 in depth=1: 2
      3) size of array 2 plus size of all array before in depth=1: 2 + 2 = 4
      After sizes info comes flatten data: 3 -> 4 -> 5 -> 6
  "
      Quoted from https://github.com/mymarilyn/clickhouse-driver/blob/master/clickhouse_driver/columns/arraycolumn.py
-}

readArray :: Int->ByteString->Reader (Vector ClickhouseType)
readArray n_rows spec = do
  (lastSpec, x:xs) <- genSpecs spec [V.fromList [fromIntegral n_rows]]
  let numElem = fromIntegral $ V.sum x
  elems <- getColumnWithSpec numElem lastSpec
  let result' = foldl combine elems (x:xs)
  let result = case (result' ! 0) of
             CKArray arr -> arr
             _ -> error "wrong type. This cannot happen"
  return result
  where  
    combine :: Vector ClickhouseType -> Vector Word64 -> Vector ClickhouseType
    combine elems config = 
      let intervals = intervalize (fromIntegral <$> config)
          cut (a, b) = CKArray $ V.take b (V.drop a elems)
          embed = (\(l, r)->cut (l, r - l + 1)) <$> intervals
      in  embed
        
    intervalize :: Vector Int -> Vector (Int, Int)
    intervalize vec = V.drop 1 $ V.scanl' (\(a, b) v->(b+1, v+b)) (-1, -1) vec

    readArraySpec :: Vector Word64->Reader (Vector Word64)
    readArraySpec sizeArr = do
      let arrSum = (fromIntegral . V.sum) sizeArr
      offsets <- V.replicateM arrSum readBinaryUInt64
      let offsets' = V.cons 0 (V.take (arrSum - 1) offsets)
      let sizes = V.zipWith (-) offsets offsets'
      return sizes

    genSpecs :: ByteString->[Vector Word64]-> Reader (ByteString, [Vector Word64])
    genSpecs spec rest@(x:xs) = do
      let l = BS.length spec
      let cktype = BS.take (l - 7) (BS.drop 6 spec)
      if "Array" `isPrefixOf` spec
        then do 
          next <- readArraySpec x
          genSpecs cktype (next:rest)
        else
          return (spec, rest)

readTuple :: Int->ByteString->Reader (Vector ClickhouseType)
readTuple n_rows spec = do
  let l = BS.length spec
  let innerSpecString = BS.take(l - 7) (BS.drop 6 spec)
  let arr = V.fromList (getSpecs innerSpecString) 
  datas <- V.mapM (getColumnWithSpec n_rows) arr
  let transposed = transpose datas
  return $ CKTuple <$> transposed


readEnum :: Int->ByteString->Reader (Vector ClickhouseType)
readEnum n_rows spec = do
  let l = BS.length spec
      innerSpec = if "Enum8" `isPrefixOf` spec 
        then BS.take(l - 7) (BS.drop 6 spec)
        else BS.take(l - 8) (BS.drop 7 spec)
      prespecs = getSpecs innerSpec
      specs = (\(name, Just (n, _))-> (n, name)) <$> ((toTuple . BS.splitWith (== 61)) <$> prespecs) --61 is '='
      specsMap = Map.fromList specs
  if "Enum8" `isPrefixOf` spec 
    then do 
      vals <- V.replicateM n_rows readBinaryInt8
      return $ (CKString . (specsMap Map.!) . fromIntegral) <$> vals
    else do
      vals <- V.replicateM n_rows readBinaryInt16
      return $ (CKString . (specsMap Map.!) . fromIntegral) <$> vals
      where
        toTuple [x, y] = (x, readInt y)

readDate :: Int->ByteString->Reader(Vector ClickhouseType)
readDate n_rows spec = do
  let epoch_start = fromGregorian 1970 1 1
  days <- V.replicateM n_rows readBinaryUInt16
  let dates = fmap (\x->addDays (fromIntegral x) epoch_start) days
      toTriple = fmap toGregorian dates
      toCK = fmap (\(y, m, d)->CKDate y m d) toTriple
  return toCK

readDecimal :: Int->ByteString->Reader(Vector ClickhouseType)
readDecimal n_rows spec = do
  let l = BS.length spec 
  let [precision', scale'] = getSpecs $ BS.take(l - 9) (BS.drop 8 spec)
  
  let (Just (precision,_), Just (scale,_)) = (readInt precision', readInt scale')

  let specific = 
        if precision <= 9
          then readDecimal32
          else if precision <= 18
            then readDecimal64
            else readDecimal128
  
  raw <- specific n_rows

  let final = fmap (trans scale) raw
  
  return final
  where
    readDecimal32 n_rows = readIntColumn n_rows "Int32"
    readDecimal64 n_rows = readIntColumn n_rows "Int64"
    readDecimal128 n_rows = undefined

    trans :: Int->ClickhouseType->ClickhouseType
    trans scale (CKInt32 x) = CKDecimal32 (fromIntegral x / fromIntegral scale)
    trans scale (CKInt64 x) = CKDecimal64 (fromIntegral x / fromIntegral scale)



---------------------------------------------------------------------------------------------
--------Helpers 

-- | Get rid of commas and spaces
getSpecs :: ByteString -> [ByteString]
getSpecs str = BS.splitWith (==44) (BS.filter ( /= 32) str) 

transpose :: Vector (Vector ClickhouseType) -> Vector (Vector ClickhouseType)
transpose cdata =
  rotate cdata
  where
    rotate matrix =
      let transposedList = List.transpose (V.toList <$> V.toList matrix)
          toVector = V.fromList <$> (V.fromList transposedList)
       in toVector

-- | print in format
format :: Vector (Vector ClickhouseType) -> String
format = undefined