{-# LANGUAGE CPP #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ForeignFunctionInterface #-}

module Main where

import           ClickHouseDriver
import           Control.Monad.ST
import           Data.Text
import qualified Data.Text.IO as TIO
import           Network.HTTP.Client
import           Data.ByteString      hiding (putStr)  
import qualified Data.ByteString.Char8 as C8
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
import           ClickHouseDriver.Core.Column
import           ClickHouseDriver.Core.HTTP.Helpers
import qualified Network.URI.Encode as NE
import qualified System.IO.Streams as Streams
import           System.IO hiding (putStr)
import           Data.Int
import           Data.Bits

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

query :: IO()
query = do
    conn <- defaultHttpConnection
    env <- setupEnv conn
    res <- runQuery env (getJSON "SHOW DATABASES")
    print res


class MyType a

instance MyType Int

instance MyType Char

instance MyType Bool

myfunc :: (MyType a)=>a->a
myfunc a = a

testByteString :: IO ByteString
testByteString = do
    (_,res) <- runWriterT $ do
        writeBinaryStr "hello"
        writeBinaryStr "world"
        writeBinaryStr "my"
        writeBinaryStr "darling"
    return res

readBinaryStrN = V.replicateM 4 readBinaryStr

testIntStr :: IO ByteString
testIntStr = do
    (_,res) <- runWriterT $ do
        writeVarUInt 2
        writeVarUInt 4
        writeVarUInt 8
        writeVarUInt 10
        writeVarUInt 12
    return res

testWriteHybrid :: IO ByteString
testWriteHybrid = do
    (_,r) <- runWriterT $ do
        writeBinaryStr "Hello"
        writeVarUInt 27
        writeVarUInt 38
        writeBinaryStr "World"
    return r

readManyVarInt :: Reader [Word]
readManyVarInt = do
    int <- readVarInt
    if int == 10 
        then
        return [10]
        else do
            next <- readManyVarInt
            return (int : next)
    
mainTest :: IO()
mainTest = do
    print "Test Section"
    conn <- defaultClient
    env <- client conn
    print "connected"
    res <- execute "select * from crd2" env
    closeConnection conn
    print res

writes ::ByteString->IO (ByteString)
writes str = do
    (_, r) <- runWriterT $ do
        writeBinaryStr str
    return r

data SocketReader = SocketReader {
    sock :: Socket,
    readFromSock :: Socket->IO(ByteString)
}

manualTCP :: IO()
manualTCP = do
    print "manual"
    conn <- defaultClient
    case conn of
        Left e -> print e
        Right settings->do
            print "connected"
            sendQuery "select * from crd2" Nothing settings
            sendData "" settings
            case settings of
                TCPConnection {tcpSocket=sock}-> do
                    x <- TCP.recv sock 2048
                    print x
                    y <- TCP.recv sock 2048
                    print y
                    z <- TCP.recv sock 2048
                    print z
                    TCP.closeSock sock
main :: IO()
main = do
    env <- httpClient "default" "12345612341"
    result <- runQuery env (getText "show tables")
    TIO.putStr result