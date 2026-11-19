import type { Server } from 'socket.io';

let io: Server | null = null;

export function setIo(server: Server) {
  io = server;
}

export function emitToUser(userId: string, event: string, payload: unknown) {
  io?.to(`user:${userId}`).emit(event, payload);
}

export function emitToRequest(requestId: string, event: string, payload: unknown) {
  io?.to(`request:${requestId}`).emit(event, payload);
}
