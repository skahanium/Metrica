import { create } from 'zustand';
import type { MessageItem, SelectionMode } from '../types/protocol';

interface MessageState {
  messages: MessageItem[];
  trash: MessageItem[];
  selectionMode: SelectionMode;
  selectedIds: Set<string>;

  // 消息操作
  addMessage: (msg: Omit<MessageItem, 'id' | 'is_deleted' | 'created_at'>) => void;
  deleteMessages: (ids: string[]) => void;
  restoreMessages: (ids: string[]) => void;
  permanentlyDeleteMessages: (ids: string[]) => void;
  clearTrash: () => void;

  // 选择操作
  setSelectionMode: (mode: SelectionMode) => void;
  toggleSelection: (id: string) => void;
  selectAll: () => void;
  clearSelection: () => void;
  getSelectedMessages: () => MessageItem[];

  // 重跑
  getRerunnableCommands: () => string[];
}

export const useMessageStore = create<MessageState>((set, get) => ({
  messages: [],
  trash: [],
  selectionMode: 'none',
  selectedIds: new Set(),

  addMessage: (msg) => set((state) => ({
    messages: [...state.messages, {
      ...msg,
      id: crypto.randomUUID(),
      is_deleted: false,
      created_at: new Date().toISOString(),
    }],
  })),

  deleteMessages: (ids) => set((state) => {
    const now = new Date().toISOString();
    const toDelete = state.messages.filter((m) => ids.includes(m.id));
    const remaining = state.messages.filter((m) => !ids.includes(m.id));
    const deletedMessages = toDelete.map((m) => ({
      ...m,
      is_deleted: true,
      deleted_at: now,
    }));
    return {
      messages: remaining,
      trash: [...state.trash, ...deletedMessages],
      selectedIds: new Set(),
      selectionMode: 'none' as SelectionMode,
    };
  }),

  restoreMessages: (ids) => set((state) => {
    const toRestore = state.trash.filter((m) => ids.includes(m.id));
    const remainingTrash = state.trash.filter((m) => !ids.includes(m.id));
    const restoredMessages = toRestore.map((m) => ({
      ...m,
      is_deleted: false,
      deleted_at: undefined,
    }));
    const allMessages = [...state.messages, ...restoredMessages]
      .sort((a, b) => Date.parse(a.created_at) - Date.parse(b.created_at));
    return {
      messages: allMessages,
      trash: remainingTrash,
    };
  }),

  permanentlyDeleteMessages: (ids) => set((state) => ({
    trash: state.trash.filter((m) => !ids.includes(m.id)),
  })),

  clearTrash: () => set({ trash: [] }),

  setSelectionMode: (mode) => set((state) => ({
    selectionMode: mode,
    selectedIds: mode === 'none' ? new Set() : state.selectedIds,
  })),

  toggleSelection: (id) => set((state) => {
    const newSet = new Set(state.selectedIds);
    if (newSet.has(id)) {
      newSet.delete(id);
    } else {
      newSet.add(id);
    }
    let mode: SelectionMode;
    if (newSet.size === 0) {
      mode = 'none';
    } else if (newSet.size === 1) {
      mode = 'single';
    } else if (newSet.size === state.messages.length) {
      mode = 'all';
    } else {
      mode = 'multi';
    }
    return { selectedIds: newSet, selectionMode: mode };
  }),

  selectAll: () => set((state) => ({
    selectedIds: new Set(state.messages.map((m) => m.id)),
    selectionMode: 'all' as SelectionMode,
  })),

  clearSelection: () => set({
    selectedIds: new Set(),
    selectionMode: 'none' as SelectionMode,
  }),

  getSelectedMessages: () => {
    const { messages, selectedIds } = get();
    return messages.filter((m) => selectedIds.has(m.id));
  },

  getRerunnableCommands: () => {
    const { messages } = get();
    return messages
      .filter((m) => m.kind === 'command' && m.command)
      .map((m) => m.command!);
  },
}));
