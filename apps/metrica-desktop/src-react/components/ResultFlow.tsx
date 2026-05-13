import React, { useRef, useEffect } from 'react';
import { Empty } from 'antd';
import { useMessageStore } from '../stores/messageStore';
import { ResultBlock } from './ResultBlock';
import { TransformResultBlock } from './TransformResultBlock';
import { DataResultBlock } from './DataResultBlock';
import { MessageToolbar } from './MessageToolbar';

export const ResultFlow: React.FC = () => {
  const containerRef = useRef<HTMLDivElement>(null);
  const messages = useMessageStore((s) => s.messages);
  const selectedIds = useMessageStore((s) => s.selectedIds);
  const toggleSelection = useMessageStore((s) => s.toggleSelection);

  const sortedMessages = [...messages].sort(
    (a, b) => Date.parse(a.created_at) - Date.parse(b.created_at)
  );

  useEffect(() => {
    if (containerRef.current) {
      containerRef.current.scrollTop = containerRef.current.scrollHeight;
    }
  }, [sortedMessages.length]);

  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column' }}>
      <MessageToolbar />
      <div ref={containerRef} style={{ flex: 1, overflow: 'auto', padding: 16 }}>
        {sortedMessages.length === 0 ? (
          <Empty description="尚无分析结果。在命令行输入 use 加载数据，然后输入 regress 等命令开始分析。" />
        ) : (
          sortedMessages.map((msg) => (
            <div
              key={msg.id}
              onClick={() => toggleSelection(msg.id)}
              style={{
                marginBottom: 12,
                borderRadius: 8,
                border: selectedIds.has(msg.id) ? '2px solid var(--m-accent)' : '1px solid var(--m-border)',
                transition: 'border 0.2s',
                cursor: 'pointer',
              }}
            >
              {msg.kind === 'transform' && msg.transform_result ? (
                <TransformResultBlock
                  command={msg.command || ''}
                  source="cli"
                  result={msg.transform_result}
                />
              ) : msg.kind === 'data' && msg.data_result ? (
                <DataResultBlock
                  command={msg.command || ''}
                  result={msg.data_result}
                />
              ) : msg.result ? (
                <ResultBlock
                  command={msg.command || ''}
                  result={msg.result}
                />
              ) : null}
            </div>
          ))
        )}
      </div>
    </div>
  );
};
