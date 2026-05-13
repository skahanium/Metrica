import React from 'react';
import { Button, Space, Typography, Popconfirm } from 'antd';
import {
  DeleteOutlined,
  CheckSquareOutlined,
  UndoOutlined,
} from '@ant-design/icons';
import { useMessageStore } from '../stores/messageStore';
import { useAppStore } from '../stores/appStore';

const { Text } = Typography;

export const MessageToolbar: React.FC = () => {
  const {
    messages, selectionMode, selectedIds,
    selectAll, clearSelection, deleteMessages,
  } = useMessageStore();
  const setTrashVisible = useAppStore((s) => s.setTrashVisible);

  const selectedCount = selectedIds.size;

  const handleDeleteSelected = () => {
    if (selectedCount > 0) {
      deleteMessages(Array.from(selectedIds));
    }
  };

  if (messages.length === 0) return null;

  return (
    <div style={{
      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      padding: '4px 16px', borderBottom: '1px solid var(--m-border)', background: 'var(--m-surface-hover)',
    }}>
      <Space size="small">
        <Button
          size="small"
          type={selectionMode === 'all' ? 'primary' : 'text'}
          icon={<CheckSquareOutlined />}
          onClick={selectionMode === 'all' ? clearSelection : selectAll}
        >
          {selectionMode === 'all' ? '取消全选' : '全选'}
        </Button>
        {selectedCount > 0 && (
          <Text type="secondary" style={{ fontSize: 12 }}>
            已选 {selectedCount} 条
          </Text>
        )}
      </Space>
      <Space size="small">
        {selectedCount > 0 && (
          <Popconfirm
            title={`确定删除 ${selectedCount} 条消息？`}
            description="删除后可从回收站恢复"
            onConfirm={handleDeleteSelected}
            okText="删除"
            cancelText="取消"
          >
            <Button size="small" danger icon={<DeleteOutlined />}>
              删除选中
            </Button>
          </Popconfirm>
        )}
        <Button
          size="small"
          icon={<UndoOutlined />}
          onClick={() => setTrashVisible(true)}
        >
          回收站
        </Button>
      </Space>
    </div>
  );
};
