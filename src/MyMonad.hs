{-# LANGUAGE GeneralizedNewtypeDeriving #-}
module MyMonad ( MyMonad
               , runMyMonad
               , indentMessages
               , debug
               , info
               , trace
               , warning
               , throwError
               , catchError
               , asks
               , gets
               , tell
               , modify
               , liftIO
               ) where

import Types

import Control.Monad.Trans (MonadIO, liftIO)
import Control.Monad.Reader (ReaderT, MonadReader, runReaderT, asks)
import Control.Monad.Writer (WriterT, MonadWriter, runWriterT, tell)
import Control.Monad.State (StateT, MonadState, evalStateT, modify, gets)
import Control.Monad.Error (ErrorT, MonadError, runErrorT, throwError, catchError)
import Control.Monad (when)
import System.IO (stderr, hPutStrLn)

import Prelude hiding (log)

newtype MyMonad a = MyMonad (StateT MyState (ReaderT Options (ErrorT MyException (WriterT [String] IO))) a)
    deriving (Monad, MonadReader Options, MonadState MyState, MonadError MyException, MonadWriter [String])

instance MonadIO MyMonad where
    liftIO m = MyMonad $ do
                 x <- liftIO $ (Right `fmap` m) `catch` (return . Left)
                 case x of
                   Left e  -> throwError $ MyException $ "IO error: " ++ show e
                   Right y -> return y

runMyMonad :: MyMonad a -> Options -> IO (Either MyException a, [String])
runMyMonad (MyMonad m) = runWriterT . runErrorT . runReaderT (evalStateT m (MyState 0))

indentMessages :: MyMonad a -> MyMonad a
indentMessages m = do
  modify (\s -> s{logDepth = logDepth s + 2})
  result <- m
  modify (\s -> s{logDepth = logDepth s - 2})
  return result

-- add message to private log and return adjusted message (with log depth)
-- that can be printed somewhere else
privateLog :: String -> MyMonad String
privateLog str = do
  depth <- gets logDepth
  let text = replicate (fromInteger depth) ' ' ++ str
  tell [text]
  return text

log :: Verbosity -> String -> MyMonad ()
log minLevel str = do
  text <- privateLog str
  flag <- asks verbosity
  when (flag >= minLevel) $
    liftIO $ putStrLn text

debug :: String -> MyMonad ()
debug = log Verbose

info :: String -> MyMonad ()
info = log Quiet

trace :: String -> MyMonad ()
trace = log VeryVerbose

warning :: String -> MyMonad ()
warning str = do
  text <- privateLog str
  liftIO $ hPutStrLn stderr text
