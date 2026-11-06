/*******************************************************************************
 * Copyright (c) 2022 IBM Corporation and others.
 * All rights reserved. This program and the accompanying materials
 * are made available under the terms of the Eclipse Public License 2.0
 * which accompanies this distribution, and is available at
 * http://www.eclipse.org/legal/epl-2.0/
 *
 * SPDX-License-Identifier: EPL-2.0
 *******************************************************************************/
import { useState, useEffect } from "react";

// bob-bridge sidecar — exposed on localhost:4000 by docker-compose.freeroam.yml
export const BOB_BRIDGE_BASE = "http://localhost:4000";

const POLL_INTERVAL_MS = 5000;

export type BridgeStatus =
  | { state: "checking" }
  | { state: "down" }
  | { state: "up"; keyConfigured: boolean };

// Probes GET /health so the UI can tell "bridge not running" apart from
// "bridge running but no Bob API key". Re-checks periodically, so starting the
// bridge after the page has loaded is picked up without a reload.
const useBridgeStatus = (): BridgeStatus => {
  const [status, setStatus] = useState<BridgeStatus>({ state: "checking" });

  useEffect(() => {
    let cancelled = false;

    const check = async () => {
      try {
        const res = await fetch(`${BOB_BRIDGE_BASE}/health`);
        if (!res.ok) {
          throw new Error(`health returned ${res.status}`);
        }
        const data = await res.json();
        if (!cancelled) {
          setStatus({ state: "up", keyConfigured: data.keyConfigured !== false });
        }
      } catch {
        if (!cancelled) {
          setStatus({ state: "down" });
        }
      }
    };

    check();
    const id = window.setInterval(check, POLL_INTERVAL_MS);
    return () => {
      cancelled = true;
      window.clearInterval(id);
    };
  }, []);

  return status;
};

export default useBridgeStatus;
