import { describe, it, expect, beforeEach } from 'vitest';
import { useMessageStore } from '../stores/messageStore';

describe('messageStore', () => {
  beforeEach(() => {
    useMessageStore.setState({ messages: [], trash: [], selectedIds: new Set(), selectionMode: 'none' });
  });

  it('adds message with auto-generated id', () => {
    const { addMessage } = useMessageStore.getState();
    addMessage({ kind: 'command', command: 'regress y x' });
    const msgs = useMessageStore.getState().messages;
    expect(msgs).toHaveLength(1);
    expect(msgs[0].command).toBe('regress y x');
    expect(msgs[0].id).toBeDefined();
    expect(msgs[0].is_deleted).toBe(false);
    expect(msgs[0].created_at).toBeDefined();
  });

  it('moves deleted messages to trash', () => {
    const { addMessage } = useMessageStore.getState();
    addMessage({ kind: 'command', command: 'cmd1' });
    addMessage({ kind: 'command', command: 'cmd2' });
    const id = useMessageStore.getState().messages[0].id;
    useMessageStore.getState().deleteMessages([id]);
    expect(useMessageStore.getState().messages).toHaveLength(1);
    expect(useMessageStore.getState().trash).toHaveLength(1);
    expect(useMessageStore.getState().trash[0].is_deleted).toBe(true);
    expect(useMessageStore.getState().trash[0].deleted_at).toBeDefined();
  });

  it('clears selection on delete', () => {
    const { addMessage } = useMessageStore.getState();
    addMessage({ kind: 'command', command: 'cmd1' });
    const id = useMessageStore.getState().messages[0].id;
    useMessageStore.getState().toggleSelection(id);
    expect(useMessageStore.getState().selectedIds.size).toBe(1);
    useMessageStore.getState().deleteMessages([id]);
    expect(useMessageStore.getState().selectedIds.size).toBe(0);
    expect(useMessageStore.getState().selectionMode).toBe('none');
  });

  it('restores messages from trash in chronological order', () => {
    const { addMessage } = useMessageStore.getState();
    addMessage({ kind: 'command', command: 'cmd1' });
    addMessage({ kind: 'command', command: 'cmd2' });
    const allIds = useMessageStore.getState().messages.map((m) => m.id);
    useMessageStore.getState().deleteMessages(allIds);
    expect(useMessageStore.getState().messages).toHaveLength(0);
    expect(useMessageStore.getState().trash).toHaveLength(2);
    useMessageStore.getState().restoreMessages(allIds);
    expect(useMessageStore.getState().messages).toHaveLength(2);
    expect(useMessageStore.getState().trash).toHaveLength(0);
    expect(useMessageStore.getState().messages[0].is_deleted).toBe(false);
    expect(useMessageStore.getState().messages[0].deleted_at).toBeUndefined();
  });

  it('permanently deletes messages from trash', () => {
    const { addMessage } = useMessageStore.getState();
    addMessage({ kind: 'command', command: 'cmd1' });
    const id = useMessageStore.getState().messages[0].id;
    useMessageStore.getState().deleteMessages([id]);
    expect(useMessageStore.getState().trash).toHaveLength(1);
    useMessageStore.getState().permanentlyDeleteMessages([id]);
    expect(useMessageStore.getState().trash).toHaveLength(0);
  });

  it('clears entire trash', () => {
    const { addMessage } = useMessageStore.getState();
    addMessage({ kind: 'command', command: 'cmd1' });
    addMessage({ kind: 'command', command: 'cmd2' });
    const ids = useMessageStore.getState().messages.map((m) => m.id);
    useMessageStore.getState().deleteMessages(ids);
    expect(useMessageStore.getState().trash).toHaveLength(2);
    useMessageStore.getState().clearTrash();
    expect(useMessageStore.getState().trash).toHaveLength(0);
  });

  it('selects and deselects messages', () => {
    const { addMessage } = useMessageStore.getState();
    addMessage({ kind: 'command', command: 'cmd1' });
    addMessage({ kind: 'command', command: 'cmd2' });
    const ids = useMessageStore.getState().messages.map((m) => m.id);
    useMessageStore.getState().toggleSelection(ids[0]);
    expect(useMessageStore.getState().selectionMode).toBe('single');
    useMessageStore.getState().selectAll();
    expect(useMessageStore.getState().selectionMode).toBe('all');
    expect(useMessageStore.getState().selectedIds.size).toBe(2);
  });

  it('toggleSelection updates mode correctly', () => {
    const { addMessage } = useMessageStore.getState();
    addMessage({ kind: 'command', command: 'cmd1' });
    addMessage({ kind: 'command', command: 'cmd2' });
    const ids = useMessageStore.getState().messages.map((m) => m.id);
    useMessageStore.getState().toggleSelection(ids[0]);
    expect(useMessageStore.getState().selectionMode).toBe('single');
    useMessageStore.getState().toggleSelection(ids[1]);
    expect(useMessageStore.getState().selectionMode).toBe('all');
    useMessageStore.getState().toggleSelection(ids[0]);
    expect(useMessageStore.getState().selectionMode).toBe('single');
    useMessageStore.getState().toggleSelection(ids[1]);
    expect(useMessageStore.getState().selectionMode).toBe('none');
  });

  it('setSelectionMode none clears selectedIds', () => {
    const { addMessage } = useMessageStore.getState();
    addMessage({ kind: 'command', command: 'cmd1' });
    const id = useMessageStore.getState().messages[0].id;
    useMessageStore.getState().toggleSelection(id);
    expect(useMessageStore.getState().selectedIds.size).toBe(1);
    useMessageStore.getState().setSelectionMode('none');
    expect(useMessageStore.getState().selectedIds.size).toBe(0);
  });

  it('getSelectedMessages returns correct items', () => {
    const { addMessage } = useMessageStore.getState();
    addMessage({ kind: 'command', command: 'cmd1' });
    addMessage({ kind: 'command', command: 'cmd2' });
    const id = useMessageStore.getState().messages[0].id;
    useMessageStore.getState().toggleSelection(id);
    const selected = useMessageStore.getState().getSelectedMessages();
    expect(selected).toHaveLength(1);
    expect(selected[0].command).toBe('cmd1');
  });

  it('getRerunnableCommands returns command strings', () => {
    const { addMessage } = useMessageStore.getState();
    addMessage({ kind: 'command', command: 'regress y x' });
    addMessage({ kind: 'command', command: 'summarize y' });
    addMessage({ kind: 'result', result: { glance: { model: 'ols', nobs: 100, dof: 2, metrics: {} }, tidy: [], diagnostics: {}, warnings: [] } });
    const cmds = useMessageStore.getState().getRerunnableCommands();
    expect(cmds).toEqual(['regress y x', 'summarize y']);
  });
});
