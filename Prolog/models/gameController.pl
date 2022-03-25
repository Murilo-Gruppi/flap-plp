:- module(controller, [initGameLoop/0]).

:- use_module(gameScreen).
:- use_module(terminal).
:- use_module(bird).
:- use_module('../utils/lists').

exitKeyNumber(113). % Key: Q
actionKeyNumber(13). % Key: Enter

gameFPS(20).
delayBetweenGameFrames(DelayInSeconds):-
  gameFPS(GameFPS),
  DelayInSeconds is 1 / GameFPS.

initGameLoop:-
  terminal:startPlayerInputThread,
  run(0, 0).

% Stops program when the exit is typed. Stops the program correctly, but causes some problems afterwards.
haltIfExitKeyWasTyped(KeyNumber):-
  exitKeyNumber(KeyNumber),
  halt,
  !.
haltIfExitKeyWasTyped(_).

processInput(CurrentState, KeyNumber, StateWithInput):-
  actionKeyNumber(KeyNumber),
  % Enter was pressed. Process input...
  StateWithInput is CurrentState + 1,
  !.
processInput(_, _, _).

run(CurrentState, Time):-
    terminal:fetchFromThread(Input),
    haltIfExitKeyWasTyped(Input),

    % terminal:getTerminalHeight(Height), This methods are commented
    % terminal:getTerminalWidth(Width),

    % Change pipes

    processInput(CurrentState, Input, StateWithInput),

    % Tick
    % Check collisions
    % Save high score

    terminal:resetCursor,
    gameScreen:render,

    delayBetweenGameFrames(DelayInSeconds),
    sleep(DelayInSeconds),
    NextTime is Time + DelayInSeconds,
    run(StateWithInput, NextTime).
