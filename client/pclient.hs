module Main where
import Control.Concurrent
import Control.Monad
import Network
import System.Environment
import System.Exit
import System.IO
import System.IO.Error

import App.Persistent.Client.Message

data EventHandler a =
    EventHandler { onRead :: ( a -> IO () ), onEof :: IO () }

startLoop :: IO a -> EventHandler a -> IO ()
startLoop reader handler  = do
  input <- newChan :: IO (Chan (Maybe a))
  let wait = do
        c <- liftM Just reader `catch` eofHandler
        writeChan input c
        case c of Just _ -> wait; Nothing -> return ();

      parse = do
        c <- readChan input
        case c of
          Just c -> onRead handler c >> parse
          Nothing -> return ()

      eofHandler e = if isEOFError e
                     then onEof handler >> return Nothing
                     else ioError e
  forkIO parse
  forkIO wait
  return () -- no need to "leak" the ThreadId

handleNetwork :: MVar Int -> String -> IO ()
handleNetwork exit line =
    case unserializeMessage line of
      NormalOutput str -> hPutStr stdout str
      ErrorOutput  str -> hPutStr stderr str
      Exit        code -> putMVar exit code

sendMessage :: Handle -> Message -> IO ()
sendMessage server msg = hPutStrLn server (serializeMessage msg)

sendStartupInfo :: Handle -> IO ()
sendStartupInfo server = do
  p <- getProgName
  a <- getArgs
  e <- getEnvironment

  mapM (sendMessage server)
           [ ProgramName p
           , CommandLineArgs a
           , Environment e
           ]
  return ()

main = do
  hSetBuffering stdin LineBuffering
  hSetBuffering stdout NoBuffering
  hSetBuffering stderr NoBuffering

  exit <- newEmptyMVar
  server <- connectTo "localhost" (PortNumber 1234)
  hSetBuffering server NoBuffering

  sendStartupInfo server

  startLoop (hGetLine server)
            EventHandler { onRead = handleNetwork exit,
                           onEof  = exitWith ExitSuccess }

  startLoop (hGetChar stdin)
            EventHandler { onRead = \c -> sendMessage server (KeyPress c),
                           onEof  = sendMessage server (EndOfFile StdIn) }

  exitCode <- takeMVar exit
  exitWith $ case exitCode of
               0 -> ExitSuccess
               _ -> ExitFailure exitCode
