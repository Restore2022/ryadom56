"""In-memory WebSocket hub for call signaling. Media stays P2P."""

from __future__ import annotations

import asyncio
import json
import logging
from typing import Any

from fastapi import WebSocket

logger = logging.getLogger(__name__)


class CallHub:
    def __init__(self) -> None:
        self._conns: dict[int, set[WebSocket]] = {}
        self._lock = asyncio.Lock()
        self.loop: asyncio.AbstractEventLoop | None = None

    def bind_loop(self, loop: asyncio.AbstractEventLoop) -> None:
        self.loop = loop

    def is_online(self, user_id: int) -> bool:
        return bool(self._conns.get(int(user_id)))

    def connected_count(self) -> int:
        return sum(1 for bucket in self._conns.values() if bucket)

    async def connect(self, user_id: int, ws: WebSocket) -> None:
        async with self._lock:
            self._conns.setdefault(user_id, set()).add(ws)

    async def disconnect(self, user_id: int, ws: WebSocket) -> None:
        async with self._lock:
            bucket = self._conns.get(user_id)
            if not bucket:
                return
            bucket.discard(ws)
            if not bucket:
                self._conns.pop(user_id, None)

    async def send(self, user_id: int, payload: dict[str, Any]) -> int:
        sockets = list(self._conns.get(int(user_id), ()))
        if not sockets:
            return 0
        text = json.dumps(payload, ensure_ascii=False, default=str)
        sent = 0
        dead: list[WebSocket] = []
        for ws in sockets:
            try:
                await ws.send_text(text)
                sent += 1
            except Exception:
                dead.append(ws)
        for ws in dead:
            await self.disconnect(user_id, ws)
        return sent

    def emit(self, user_id: int, payload: dict[str, Any]) -> None:
        loop = self.loop
        if loop is None or not loop.is_running():
            return
        try:
            asyncio.run_coroutine_threadsafe(self.send(int(user_id), payload), loop)
        except Exception as exc:
            logger.warning("call hub emit failed user=%s: %s", user_id, exc)


hub = CallHub()
