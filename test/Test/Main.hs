{-# LANGUAGE CPP #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ForeignFunctionInterface #-}
module Main where

import           ClickHouseDriver.Core
import           ClickHouseDriver.Core.HTTP
import           Control.Monad.ST
import           Data.Text
import qualified Data.Text.IO as TIO
import           Network.HTTP.Client
import           Data.ByteString      hiding (putStr)  
import qualified Data.ByteString.Char8 as C8
import qualified Data.ByteString.Lazy.Char8 as CL8
import           Foreign.C
import           ClickHouseDriver.IO.BufferedWriter
import           ClickHouseDriver.IO.BufferedReader
import           Data.Monoid
import           Control.Monad.State.Lazy
import           Data.ByteString.Builder
import qualified Data.ByteString.Lazy as L
import           Data.Word
import           Network.Socket                                           
import qualified Network.Simple.TCP as TCP
import qualified Data.Binary as B
import           Data.Int
import           Control.Monad.Writer
import qualified Data.Vector as V
import qualified Control.Monad.Reader as R
import           Control.Monad.Reader (ask)
import qualified ClickHouseDriver.Core.Column as Col
import           ClickHouseDriver.Core.HTTP.Helpers
import qualified Network.URI.Encode as NE
import qualified System.IO.Streams as Streams
import           System.IO hiding (putStr)
import           Data.Int
import           Data.Bits
import           Haxl.Core

someReader :: R.Reader Int Int
someReader = do
    x <- ask
    return (x + 1)

xReader :: R.Reader Socket ByteString
xReader = undefined

readResult :: Reader Word
readResult = do
    r <- readVarInt
    r2 <- readVarInt
    r3 <- readVarInt
    return r3

readResult2 :: Reader ByteString
readResult2 = do
    r <- readBinaryStr
    r' <- readBinaryStr
    return (r <> r')

main3 :: IO()
main3 = do
    (sock, sockaddr) <- TCP.connectSock "localhost" "9000"
    print sock

class MyType a

instance MyType Int

instance MyType Char

instance MyType Bool

myfunc :: (MyType a)=>a->a
myfunc a = a

readManyVarInt :: Reader [Word]
readManyVarInt = do
    int <- readVarInt
    if int == 10 
        then
        return [10]
        else do
            next <- readManyVarInt
            return (int : next)

manualTCP :: IO()
manualTCP = do
    print "manual"
    conn' <- tcpConnect "localhost" "9000" "default" "12345612341" "default" False
    case conn' of
        Left _ -> return ()
        Right conn -> do
            print "connected"
            sendQuery conn "select * from tande" Nothing
            sendData conn "" Nothing
            case conn of
                TCPConnection {tcpSocket=sock}-> do
                    x <- TCP.recv sock 2048
                    print x
                    y <- TCP.recv sock 2048
                    print y
                    z <- TCP.recv sock 2048
                    print z
                    TCP.closeSock sock
        


mainTest :: IO()
mainTest = do
    print "Test Section"
    conn <- defaultClient
    print "connected"
    res <- query "select item from array_t" conn
    closeClient conn
    print res


writes ::ByteString->IO (ByteString)
writes str = do
    r <- execWriterT $ do
        writeBinaryStr str
    return r

data SocketReader = SocketReader {
    sock :: Socket,
    readFromSock :: Socket->IO(ByteString)
}

main' :: IO()
main' = do
    env <- httpClient "default" "12345612341"
    create <- exec "CREATE TABLE test (x Int32) ENGINE = Memory" env
    print create
    isSuccess <- ClickHouseDriver.Core.HTTP.insertOneRow "test" [CKInt32 100] env
    print isSuccess
    result <- runQuery env (getText "select * from test")
    TIO.putStr result

main'' :: IO()
main'' = do
    env <- httpClient "default" "12345612341"
    isSuccess <- insertFromFile "test_table" CSV "./test/example.csv" env
    putStr (case isSuccess of
        Right y -> y
        Left x -> CL8.unpack x)
    query <- runQuery env (getText "SELECT * FROM test_table")
    TIO.putStr query

insertTest :: IO()
insertTest = do
    print "insertion test"
    conn <- defaultClient
    s <- ClickHouseDriver.Core.insertMany conn "INSERT INTO simple_table VALUES" 
            [[CKString "0000000000", CKString "Clickhouse-Haskell", CKInt16 1]
            ,[CKString "1000000000", CKString "Clickhouse-Haskell2", CKInt16 12]
            ,[CKString "3000000000", CKString "Clickhouse-Haskell3", CKInt16 15]]
    print s
    q <- query "SELECT * FROM simple_table" conn
    print q
    closeClient conn

readTest :: IO ()
readTest = do
    cmd <- System.IO.getLine
    conn <- defaultClient
    res <- query cmd conn
    print res
    closeClient conn
--INSERT INTO nulls_table (`id`, `item`,`number`) VALUES (null, 'JOHN',1557),('1234567890', null,533),('3543364534', 'MARRY',null),('2258864346', 'JAME',4452)
insertTest2 :: IO()
insertTest2 = do
    conn <- defaultClient
    s <- ClickHouseDriver.Core.insertMany conn "INSERT INTO nulls_table VALUES" 
            [[CKNull, CKString "Clickhouse-Haskell", CKInt16 1]
            ,[CKString "1000000000", CKNull, CKInt16 12]
            ,[CKString "3000000000", CKString "Clickhouse-Haskell3", CKNull]
            ,[CKString "2258864346", CKString "Jame", CKInt16 4452]]
    q <- query "SELECT * FROM nulls_table" conn
    print q 
    print "conn"
    closeClient conn

insertTest3 :: IO()
insertTest3 = do
    conn <- defaultClient
    s <- ClickHouseDriver.Core.insertMany conn "INSERT INTO tande VALUES"
            [
                [CKString "ggo", CKTuple $ V.fromList [CKInt16 0, CKString "hah", CKString "oxo", CKInt8 (-11)], CKString "hello"],
                [CKString "ggo", CKTuple $ V.fromList [CKInt16 0, CKString "hah", CKString "oxo", CKInt8 (-11)], CKString "hello"],
                [CKString "gfo", CKTuple $ V.fromList [CKInt16 0, CKString "hah", CKString "oxo", CKInt8 (-11)], CKString "world"]
            ]
    q <- query "SELECT * FROM tande" conn
    print q
    print "conn"
    closeClient conn

insertTest4 :: IO()
insertTest4 = do
    conn <- defaultClient
    s <- ClickHouseDriver.Core.insertMany conn "INSERT INTO array_table VALUES"
            [
                [CKNull, CKArray $ V.fromList [CKArray $ V.fromList [CKInt16 1], CKArray $ V.fromList [CKInt16 2], CKArray $ V.fromList [CKInt16 3]]],
                [CKNull, CKArray $ V.fromList [CKArray $ V.fromList [CKInt16 1, CKInt16 2], CKArray $ V.fromList [CKInt16 3, CKInt16 4], CKArray $ V.fromList [CKInt16 5, CKInt16 6]]]
            ]
    q <- query "SELECT * FROM array_table" conn
    print q
    print "conn"
    closeClient conn

insertTest5 :: IO()
insertTest5 = do
    conn <- defaultClient
    s <- ClickHouseDriver.Core.insertMany conn "INSERT INTO array_nulls VALUES"
            [
                [CKNull, CKArray $ V.fromList [CKArray $ V.fromList [CKString "ABC", CKNull, CKString "XYZ"], CKArray $ V.fromList [CKString "DEF"], CKArray $ V.fromList [CKString "DEF"]]],
                [CKNull, CKArray $ V.fromList [CKArray $ V.fromList [CKString "Clickhouse"],  CKArray $ V.fromList [CKNull,CKNull]]]
            ]
    q <- query "SELECT * FROM array_nulls" conn
    print q
    print "conn"
    closeClient conn

insertTest6 = do
    conn <- defaultClient
    q <- query "SELECT * FROM UUID_test" conn
    Col.putStrLn q
    closeClient conn

insertTest7 = do
    conn <- defaultClient
    q <- ClickHouseDriver.Core.insertMany conn "INSERT INTO crd VALUES"
            [
                [CKString "123", CKString "hi"],
                [CKString "456", CKString "lo"]
            ]
    closeClient conn

pingTest = do
    conn <- defaultClient
    ClickHouseDriver.Core.ping conn

main = readTest