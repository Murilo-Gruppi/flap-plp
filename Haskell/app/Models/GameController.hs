{-# LANGUAGE BlockArguments #-}

module Models.GameController where

import Control.Concurrent (threadDelay)
import Models.Area (Area (Area))
import qualified Models.Area as Area
import Models.Bird (Bird (Bird))
import qualified Models.Bird as Bird
import qualified Models.GameScreen as GameScreen
import Models.GameState (GameState (GameState))
import qualified Models.GameState as GameState
import qualified Models.LocalStorage as LocalStorage
import Models.Pipe (Pipe (Pipe))
import qualified Models.Pipe as Pipe
import Models.PipeGroup (PipeGroup)
import qualified Models.PipeGroup as PipeGroup
import Models.Terminal (Terminal (Terminal))
import qualified Models.Terminal as Terminal
import System.Random (Random (randomR), getStdRandom)

microSecondsInASecond :: Int
microSecondsInASecond = 1000000

gameFPS :: Int
gameFPS = 20

delayBetweenGameFrames :: Int
delayBetweenGameFrames = microSecondsInASecond `div` gameFPS

gravity :: Float
gravity = 0.2

birdTickFPS :: Int
birdTickFPS = 20

scoreTickFPS :: Int
scoreTickFPS = 20

pipeTickFPS :: Int
pipeTickFPS = 20

birdJumpVerticalSpeed :: Float
birdJumpVerticalSpeed = -1

timeBetweenPipeCreations :: Int
timeBetweenPipeCreations = 2000000

pipeWidth :: Int
pipeWidth = 5

pipeGroupOriginY :: Int
pipeGroupOriginY = 0

pipeGroupHoleHeight :: Int
pipeGroupHoleHeight = 10

birdOriginX :: Int
birdOriginX = 5

data GameController = GameController
  {gameState :: GameState, terminal :: Terminal}

createNewGameState:: GameState.ScreenType -> IO GameState
createNewGameState initialScreen = do
  let bird = Bird birdOriginX initialBirdOriginY 0

  highestScore <- LocalStorage.readHighScore

  return (GameState bird [] 0 highestScore initialScreen)

createGameController :: IO GameController
createGameController = do
  terminal <- Terminal.createTerminal
  terminalHeight <- Terminal.getTerminalHeight

  let initialBirdOriginY = terminalHeight `div` 2 - 3

  gameState <- createNewGameState GameState.PAUSED
  let gameController = GameController gameState terminal

  return gameController

initGameLoop :: IO ()
initGameLoop = do
  gameController <- createGameController
  run gameController 0

run :: GameController -> Int -> IO ()
run controller elapsedTime = do
  let inputChar = Terminal.inputChar (terminal controller)
  lastCharacter <- Terminal.takeLastReceivedCharacter inputChar

  let shouldStop = lastCharacter == Just Terminal.interruptSignal
  if shouldStop
    then return ()
    else do
      terminalHeight <- Terminal.getTerminalHeight
      terminalWidth <- Terminal.getTerminalWidth
      holeOriginY <- genRandomPipeHeights 3 (terminalHeight - pipeGroupHoleHeight - 5)

      let pipeGroupHeight = terminalHeight - pipeGroupOriginY - 2
      let pipeGroupOriginX = terminalWidth + 1
      let setHoleOriginY = holeOriginY

      let currentState = setPipeGroupToState (gameState controller) elapsedTime pipeGroupOriginX setHoleOriginY pipeGroupHeight

      let stateWithInput = handlePlayerInput currentState lastCharacter
      let tickedStateWithInput =
            if GameState.screenType (gameState controller) == GameState.PLAYING
              then tick stateWithInput elapsedTime terminalWidth
              else stateWithInput

      let tickedStateAfterCheck = checkCollision tickedStateWithInput terminalHeight

      Terminal.resetStylesAndCursor
      GameScreen.render tickedStateAfterCheck

      threadDelay delay

      run (setGameState controller tickedStateWithInput) (elapsedTime + delay)
  where
    delay = delayBetweenGameFrames

handlePlayerInput :: GameState -> Maybe Char -> GameState
handlePlayerInput state playerInput =
  if playerInput == Just '\n'
    then
      if GameState.screenType state == GameState.PLAYING
        then GameState.jumpBird state (GameState.bird state)
        else GameState.setScreenType state GameState.PLAYING
    else state

genRandomPipeHeights :: Int -> Int -> IO Int
genRandomPipeHeights x y = getStdRandom (randomR (x, y))

setPipeGroupToState :: GameState -> Int -> Int -> Int -> Int -> GameState
setPipeGroupToState state elapsedTime originX holeOriginY pipeGroupHeight =
  if shouldCreatePipeGroup
    then newState
    else state
  where
    shouldCreatePipeGroup =
      GameState.screenType state == GameState.PLAYING
        && elapsedTime `mod` timeBetweenPipeCreations == 0
    newPipeGroupList = GameState.pipeGroups state ++ [newPipeGroup]
    newPipeGroup = PipeGroup.create originX pipeGroupOriginY pipeWidth pipeGroupHeight holeOriginY pipeGroupHoleHeight
    newState = GameState.setPipeGroups state newPipeGroupList

tick :: GameState -> Int -> Int -> GameState
tick state elapsedTime width =
  tickScoreIfNecessary
    (tickBirdIfNecessary (tickPipeGroupsIfNecessary state elapsedTime) elapsedTime)
    elapsedTime

tickBirdIfNecessary :: GameState -> Int -> GameState
tickBirdIfNecessary state elapsedTime =
  if shouldTickBird
    then GameState.setBird state (Bird.tick bird gravity)
    else state
  where
    shouldTickBird =
      elapsedTime `mod` (microSecondsInASecond `div` birdTickFPS) == 0
    bird = GameState.bird state

tickScoreIfNecessary :: GameState -> Int -> GameState
tickScoreIfNecessary state elapsedTime =
  if shouldAddScore
    then GameState.incrementScore state scoreIncrement
    else state
  where
    shouldAddScore = elapsedTime `mod` (microSecondsInASecond `div` scoreTickFPS) == 0
    scoreIncrement = 1

tickPipeGroupsIfNecessary :: GameState -> Int -> GameState
tickPipeGroupsIfNecessary state elapsedTime =
  if shouldTickPipe
    then GameState.setPipeGroups state (removePipeGroupIfNecessary (tickAllPipeGroups pipeGroup))
    else state
  where
    shouldTickPipe = elapsedTime `mod` (microSecondsInASecond `div` pipeTickFPS) == 0
    pipeGroup = GameState.pipeGroups state

tickAllPipeGroups :: [PipeGroup.PipeGroup] -> [PipeGroup.PipeGroup]
tickAllPipeGroups pipeGroupList = [PipeGroup.tick pipeGroup | pipeGroup <- pipeGroupList]

removePipeGroupIfNecessary :: [PipeGroup.PipeGroup] -> [PipeGroup.PipeGroup]
removePipeGroupIfNecessary pipeGroups =
  if not (null pipeGroups) && PipeGroup.originX (head pipeGroups) + pipeWidth <= 0
    then tail pipeGroups
    else pipeGroups

setGameState :: GameController -> GameState -> GameController
setGameState controller newState =
  GameController newState (terminal controller)

checkCollision :: GameState -> Int -> GameState
checkCollision state terminalHeight =
  if (Bird.getOriginY bird < 0 || Bird.getOriginY bird + Bird.getHeight bird >= terminalHeight) || isCollidingWithPipes state pipeGroups
    then GameState.setScreenType state GameState.GAMEOVER
    else state
  where
    bird = GameState.bird state
    pipeGroups = GameState.pipeGroups state

gameOver :: GameState -> IO(GameState)
gameOver state = do
  if (GameState.score state > GameState.highestScore state) then
    LocalStorage.saveHighScore $ GameState.score state
  else
    return()

  return (createNewGameState GameState.PLAYING)





isCollidingWithPipes :: GameState -> [PipeGroup] -> Bool
isCollidingWithPipes state [] = False
isCollidingWithPipes state (headPipeGroup : tailPipeGroup) =
  not (null tailPipeGroup)
    && ( Area.overlapsWith (Bird.getArea bird) (PipeGroup.getArea headPipeGroup) || Area.overlapsWith (Bird.getArea bird) (PipeGroup.getArea (head tailPipeGroup))
       )
  where
    bird = GameState.bird state
