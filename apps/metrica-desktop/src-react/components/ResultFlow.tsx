import React, { useRef, useEffect } from 'react';
import { Alert, Empty } from 'antd';
import { useMessageStore } from '../stores/messageStore';
import { useAppStore } from '../stores/appStore';
import { ResultBlock } from './ResultBlock';
import { TransformResultBlock } from './TransformResultBlock';
import { DataResultBlock } from './DataResultBlock';
import { MessageToolbar } from './MessageToolbar';

interface ResultFlowProps {
  onRerun: (command: string) => void;
}

export const ResultFlow: React.FC<ResultFlowProps> = ({ onRerun }) => {
  const containerRef = useRef<HTMLDivElement>(null);
  const messages = useMessageStore((s) => s.messages);
  const selectedIds = useMessageStore((s) => s.selectedIds);
  const toggleSelection = useMessageStore((s) => s.toggleSelection);
  const teachingEnabled = useAppStore((s) => s.teachingEnabled);

  const sortedMessages = [...messages].sort(
    (a, b) => Date.parse(a.created_at) - Date.parse(b.created_at)
  );

  useEffect(() => {
    if (containerRef.current) {
      containerRef.current.scrollTop = containerRef.current.scrollHeight;
    }
  }, [sortedMessages.length]);

  const parseCommandVerb = (command?: string): string | null => {
    const trimmed = command?.trim();
    if (!trimmed) return null;
    return trimmed.split(/\s+/)[0]?.toLowerCase() ?? null;
  };

  const isDataViewingVerb = (verb: string | null): boolean =>
    verb === 'describe' || verb === 'browse' || verb === 'summarize' || verb === 'tabulate';

  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column' }}>
      <MessageToolbar />
      <div ref={containerRef} style={{ flex: 1, overflow: 'auto', padding: 16 }}>
        {sortedMessages.length === 0 ? (
          <Empty description="尚无分析结果。在命令行输入 use 加载数据，然后输入 regress 等命令开始分析。" />
        ) : (
          sortedMessages.map((msg) => (
            (() => {
              const commandVerb = parseCommandVerb(msg.command);
              const isLegacyDataModelResult = Boolean(msg.result) && isDataViewingVerb(commandVerb);

              return (
            <div
              key={msg.id}
              onClick={() => toggleSelection(msg.id)}
              style={{
                marginBottom: 12,
                borderRadius: 8,
                border: selectedIds.has(msg.id) ? '2px solid #1677ff' : '1px solid #f0f0f0',
                transition: 'border 0.2s',
                cursor: 'pointer',
              }}
            >
              {msg.kind === 'transform' && msg.transform_result ? (
                <TransformResultBlock
                  command={msg.command || ''}
                  source="cli"
                  result={msg.transform_result}
                  onRerun={onRerun}
                />
              ) : msg.kind === 'data' && msg.data_result ? (
                <DataResultBlock
                  command={msg.command || ''}
                  result={msg.data_result}
                />
              ) : isLegacyDataModelResult ? (
                <div style={{ padding: 16 }}>
                  <div style={{ marginBottom: 8 }}>
                    <Alert
                      type="error"
                      showIcon
                      message="检测到旧版错误结果"
                      description="当前消息把数据查看命令错误地渲染成了模型结果。为避免继续误导，这里不再显示“模型 / 参数 / p 值”卡片。请重启桌面端与 runtime 后重新运行该命令。"
                    />
                  </div>
                </div>
              ) : msg.result ? (
                <ResultBlock
                  command={msg.command || ''}
                  result={msg.result}
                  teachingEnabled={teachingEnabled}
                  onRerun={onRerun}
                />
              ) : null}
            </div>
              );
            })()
          ))
        )}
      </div>
    </div>
  );
};
