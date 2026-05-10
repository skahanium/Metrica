import React, { useState, useCallback } from 'react';
import { Input, Typography, Tag, Space, Tooltip, message } from 'antd';
import { useDatasetStore } from '../stores/datasetStore';
import { useCommandStore } from '../stores/commandStore';
import { executeDataOperations } from '../services/dataOperationExecutor';

const { Text } = Typography;

export const VariableWindow: React.FC = () => {
  const summary = useDatasetStore((s) => s.summary);
  const selectedVariable = useDatasetStore((s) => s.selectedVariable);
  const setSelectedVariable = useDatasetStore((s) => s.setSelectedVariable);
  const renameVariable = useDatasetStore((s) => s.renameVariable);
  const [searchText, setSearchText] = useState('');
  const [editingName, setEditingName] = useState<string | null>(null);
  const [editValue, setEditValue] = useState('');

  const columns = summary?.columns || [];
  const filteredColumns = searchText
    ? columns.filter((col) => col.name.toLowerCase().includes(searchText.toLowerCase()))
    : columns;

  // 单击：插入变量名到 CLI
  const handleClick = useCallback((name: string) => {
    setSelectedVariable(name);
    const store = useCommandStore.getState();
    const currentInput = store.input;
    const newInput = currentInput ? `${currentInput} ${name}` : name;
    store.setInput(newInput, newInput.length);
  }, [setSelectedVariable]);

  // 双击：触发重命名
  const handleDoubleClick = useCallback((name: string) => {
    setEditingName(name);
    setEditValue(name);
  }, []);

  // 确认重命名
  const handleRenameConfirm = useCallback(async () => {
    if (!editingName || !editValue || editValue === editingName) {
      setEditingName(null);
      return;
    }

    try {
      await executeDataOperations({
        operations: [{ op: 'rename', args: { mapping: { [editingName]: editValue } } }],
        commandLabel: `rename ${editingName} ${editValue}`,
        source: 'ui',
      });
      renameVariable(editingName, editValue);
      message.success(`变量 ${editingName} 已重命名为 ${editValue}`);
    } catch (e) {
      message.error(e instanceof Error ? e.message : '重命名失败');
    } finally {
      setEditingName(null);
    }
  }, [editingName, editValue, renameVariable]);

  if (!summary) {
    return (
      <div style={{ padding: 12 }}>
        <Text type="secondary" style={{ fontSize: 12 }}>加载数据后显示变量列表。</Text>
      </div>
    );
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
      <div style={{ padding: '8px 12px', borderBottom: '1px solid #f0f0f0' }}>
        <Text strong style={{ fontSize: 13 }}>变量窗口</Text>
        <Text type="secondary" style={{ fontSize: 11, marginLeft: 8 }}>({columns.length})</Text>
      </div>
      <div style={{ padding: '4px 12px', borderBottom: '1px solid #f0f0f0' }}>
        <Input
          size="small"
          placeholder="搜索变量..."
          value={searchText}
          onChange={(e) => setSearchText(e.target.value)}
          allowClear
        />
      </div>
      <div style={{ flex: 1, overflow: 'auto', padding: '4px 0' }}>
        {filteredColumns.map((col) => (
          <div
            key={col.name}
            onClick={() => handleClick(col.name)}
            onDoubleClick={() => handleDoubleClick(col.name)}
            style={{
              padding: '6px 12px',
              cursor: 'pointer',
              background: selectedVariable === col.name ? '#e6f4ff' : 'transparent',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'space-between',
              transition: 'background 0.2s',
            }}
            onMouseEnter={(e) => {
              if (selectedVariable !== col.name) e.currentTarget.style.background = '#fafafa';
            }}
            onMouseLeave={(e) => {
              if (selectedVariable !== col.name) e.currentTarget.style.background = 'transparent';
            }}
          >
            {editingName === col.name ? (
              <Input
                size="small"
                value={editValue}
                onChange={(e) => setEditValue(e.target.value)}
                onPressEnter={handleRenameConfirm}
                onBlur={handleRenameConfirm}
                autoFocus
                style={{ width: '100%' }}
              />
            ) : (
              <>
                <Tooltip title="单击插入命令行，双击重命名">
                  <Text
                    strong
                    style={{ fontSize: 13, flex: 1, overflow: 'hidden', textOverflow: 'ellipsis' }}
                  >
                    {col.name}
                  </Text>
                </Tooltip>
                <Space size={4}>
                  <Tag
                    color={col.inferred_type === 'continuous' || col.type === 'Float64' ? 'blue' : 'green'}
                    style={{ fontSize: 10, lineHeight: '16px', margin: 0 }}
                  >
                    {col.inferred_type || col.type || '?'}
                  </Tag>
                  {col.missing_count != null && col.missing_count > 0 && (
                    <Tag color="gold" style={{ fontSize: 10, lineHeight: '16px', margin: 0 }}>
                      缺失 {col.missing_count}
                    </Tag>
                  )}
                </Space>
              </>
            )}
          </div>
        ))}
      </div>
    </div>
  );
};
