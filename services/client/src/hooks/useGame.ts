/*******************************************************************************
 * Copyright (c) 2022, 2023 IBM Corporation and others.
 * All rights reserved. This program and the accompanying materials
 * are made available under the terms of the Eclipse Public License 2.0
 * which accompanies this distribution, and is available at
 * http://www.eclipse.org/legal/epl-2.0/
 *
 * SPDX-License-Identifier: EPL-2.0
 *******************************************************************************/
import { useState, useEffect, useRef } from "react";

import useSound from "use-sound";
import crashSoundFile from "assets/sounds/crash.wav";
import sunCrashSoundFile from "assets/sounds/sun_crash.wav";
import scoreSoundFile from "assets/sounds/score.mp3";
import timerSoundFile from "assets/sounds/timer.mp3";
import shortTimerSoundFile from "assets/sounds/short_timer.wav";

import { gameDurationSeconds } from "lib/config";
import useTimer from "./useTimer";
import useKeyboardColours from "./useKeyboardColours";
import useGameModes from "./useGameModes";

export enum GameState {
  Connecting,
  Error,
  Waiting,
  NotStarted,
  InGame,
  GameEnded,
}

enum Event {
  ConnectGUI = "connectGUI",
  ConnectGesture = "connectGesture",
  ServerReady = "serverReady",
  Start = "startGame",
  Health = "hp",
  Score = "score",
  PlanetChange = "planetChange",
  End = "endGame",
  Error = "error",
  Battery = "battery",
}

const MSG_DELIMITER = "|";

const formatMessage = (event: Event, data: string = "") => {
  return `${event}${MSG_DELIMITER}${data}`;
};

const FREE_ROAM_MODE = "5";

const useGame = (
  gameSocketURL: string,
  durationInSeconds: number = gameDurationSeconds
) => {
  const [gameState, setGameState] = useState(GameState.Connecting);
  const socket = useRef<WebSocket | null>(null);
  const [playerName, setPlayerName] = useState("");
  const [gameMode, setGameMode] = useState("5");
  const [health, setHealth] = useState(100);
  const [score, setScore] = useState(0);
  const [battery, setBattery] = useState(-1);
  const [error, setError] = useState("");

  const [, { sound: crashSound }] = useSound(crashSoundFile, {
    volume: 0.5,
    playbackRate: 1.5,
  });
  const [, { sound: sunCrashSound }] = useSound(sunCrashSoundFile);
  const [, { sound: scoreSound }] = useSound(scoreSoundFile);
  const [, { sound: timerSound }] = useSound(timerSoundFile);
  const [, { sound: shortTimerSound }] = useSound(shortTimerSoundFile);

  const { formattedTime, timeRemaining, startTimer, stopTimer } =
    useTimer(durationInSeconds);

  useKeyboardColours(socket.current, gameState);

  const gameModes = useGameModes();

  useEffect(() => {
    socket.current = new WebSocket(gameSocketURL);
    return () => {
      socket.current?.close();
      socket.current = null;
    };
  }, [gameSocketURL]);

  useEffect(() => {
    if (!socket.current) return;

    socket.current.onopen = () => {
      sendMessage(Event.ConnectGUI);
      sendMessage(Event.ConnectGesture);
      setGameState(GameState.Waiting);
    };
    socket.current.onerror = () => {
      setError("Failed to connect to game service.");
      setGameState(GameState.Error);
    };
    socket.current.onmessage = (ev) => {
      const [event, data] = ev.data.split(MSG_DELIMITER);
      switch (event) {
        case Event.ConnectGUI:
        case Event.ConnectGesture:
        case Event.Start:
          // do nothing; these are client events
          break;
        case Event.ServerReady:
          setGameState(GameState.NotStarted);
          break;
        case Event.Health: {
          const [newHealthStr, obstacle] = data.split(",");
          const newHealth = parseInt(newHealthStr);
          if (newHealth < health) {
            if (obstacle === "sun") {
              sunCrashSound?.play();
            } else {
              crashSound?.play();
            }
          }
          setHealth(newHealth);
          break;
        }
        case Event.Score: {
          const newScore = parseInt(data);
          if (newScore > score) {
            scoreSound?.play();
            shortTimerSound?.stop();
          }
          setScore(newScore);
          break;
        }
        case Event.PlanetChange:
          shortTimerSound?.play();
          break;
        case Event.End:
          stopTimer();
          timerSound?.stop();
          setGameState(GameState.GameEnded);
          break;
        case Event.Error:
          setError(data);
          setGameState(GameState.Error);
          break;
        case Event.Battery:
          setBattery(parseInt(data));
          break;
        default:
          console.log(`Received unknown event: ${event}`);
      }
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [
    socket,
    crashSound,
    sunCrashSound,
    scoreSound,
    timerSound,
    shortTimerSound,
    health,
    score,
    battery,
  ]);

  useEffect(() => {
    if (timeRemaining === 10) {
      timerSound?.play();
    }
    if (timeRemaining === 0) {
      endGame();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [timeRemaining, timerSound]);

  function startGame(playerName: string, gameMode: string) {
    if (gameState === GameState.NotStarted) {
      setPlayerName(playerName);
      setGameMode(gameMode);
      sendMessage(Event.Start, [encodeURIComponent(playerName), gameMode].join(","));
      setGameState(GameState.InGame);
      // Free Roam has no countdown timer
      if (gameMode !== FREE_ROAM_MODE) {
        startTimer();
      }
    }
  }

  function endGame() {
    if (gameState === GameState.InGame) {
      sendMessage(
        Event.End,
        gameMode === FREE_ROAM_MODE
          ? ""
          : String(durationInSeconds - timeRemaining)
      );
    }
  }

  function sendMessage(event: Event, data: string = "") {
    socket.current?.send(formatMessage(event, data));
  }

  return {
    playerName,
    gameMode,
    gameModes,
    gameState,
    formattedTime,
    timeRemaining,
    health,
    score,
    startGame,
    endGame,
    error,
    battery,
    socket: socket.current,
  };
};

export default useGame;
