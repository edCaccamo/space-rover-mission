/*******************************************************************************
 * Copyright (c) 2022, 2023 IBM Corporation and others.
 * All rights reserved. This program and the accompanying materials
 * are made available under the terms of the Eclipse Public License 2.0
 * which accompanies this distribution, and is available at
 * http://www.eclipse.org/legal/epl-2.0/
 *
 * SPDX-License-Identifier: EPL-2.0
 *******************************************************************************/
import React from "react";
import { Navigate } from "react-router-dom";
import PlayerForm from "components/PlayerForm";
import GameScreen from "components/GameScreen";
import FreeRoamScreen from "components/FreeRoamScreen";
import GameStateMessage from "components/GameStateMessage";
import BatteryStatus from "components/BatteryStatus";
import useGame, { GameState, FREE_ROAM_MODE } from "hooks/useGame";
import useBridgeStatus from "hooks/useBridgeStatus";
import { gameSocketURL, gameDurationSeconds } from "lib/config";

// Free Roam needs bob-bridge: it is where the list of rover scripts comes from.
const BRIDGE_DOWN_MESSAGE =
  "Free Roam is unavailable: the bob-bridge container is not running, so there are no tricks to run. " +
  "Start it with: podman-compose -f docker-compose.yml -f docker-compose.freeroam.yml up -d";
const BRIDGE_CHECKING_MESSAGE = "Checking whether Free Roam is available...";

const PlayPage = () => {
  const {
    playerName,
    gameMode,
    gameModes,
    gameState,
    formattedTime,
    health,
    score,
    startGame,
    error,
    battery,
    socket,
  } = useGame(gameSocketURL, gameDurationSeconds);
  const bridge = useBridgeStatus();

  let freeRoamBlockedReason: string | null = null;
  if (bridge.state === "down") {
    freeRoamBlockedReason = BRIDGE_DOWN_MESSAGE;
  } else if (bridge.state === "checking") {
    freeRoamBlockedReason = BRIDGE_CHECKING_MESSAGE;
  }

  switch (gameState) {
    case GameState.Connecting:
    case GameState.Error:
    case GameState.Waiting:
    case GameState.NotStarted:
      return (
        <div className="flex flex-col gap-7 justify-center h-full">
          <PlayerForm
            gameModes={gameModes}
            isDisabled={gameState !== GameState.NotStarted}
            onSubmit={startGame}
            freeRoamBlockedReason={freeRoamBlockedReason}
          />
          <GameStateMessage
            state={gameState}
            errorMessage={error}
          />
          <BatteryStatus
            batteryPercentage={battery}
          />
        </div>
      );
    case GameState.InGame:
      if (gameMode === FREE_ROAM_MODE) {
        return (
          <FreeRoamScreen
            playerName={playerName}
            gameMode={gameMode}
            socket={socket}
            bobKeyConfigured={bridge.state === "up" && bridge.keyConfigured}
          />
        );
      }
      return (
        <GameScreen
          playerName={playerName}
          gameMode={gameMode}
          health={health}
          score={score}
          time={formattedTime}
        />
      );
    case GameState.GameEnded:
      return (
        <Navigate
          to={`/leaderboard?player=${encodeURIComponent(playerName)}&gameMode=${gameMode}`}
        />
      );
    default:
      return null;
  }
};

export default PlayPage;
