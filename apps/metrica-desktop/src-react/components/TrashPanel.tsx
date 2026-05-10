import React, { useState } from 'react';
import { Modal, List, Button, Space, Typography, Empty, Popconfirm } from 'antd';
import { UndoOutlined, DeleteOutlined, ClearOutlined } from '@ant-design/icons';
import { useMessageStore } from '../stores/messageStore';
import { useAppStore } from '../stores/appStore';

const { Text } = Typography;

export const TrashPanel: React.FC = () => {
  const trashVisible = useAppStore((s) => s.trashVisible);
  const setTrashVisible = useAppStore((s) => s.setTrashVisible);
  const { trash, restoreMessages, permanentlyDeleteMessages, clearTrash } = useMessageStore();
  const [selectedTrashIds, setSelectedTrashIds] = useState<Set<string>>(new Set());

  const handleRestore = () => {
    if (selectedTrashIds.size > 0) {
      restoreMessages(Array.from(selectedTrashIds));
      setSelectedTrashIds(new Set());
    }
  };

  const handlePermanentDelete = () => {
    if (selectedTrashIds.size > 0) {
      permanentlyDeleteMessages(Array.from(selectedTrashIds));
      setSelectedTrashIds(new Set());
    }
  };

  const toggleTrashSelection = (id: string) => {
    const newSet = new Set(selectedTrashIds);
    if (newSet.has(id)) {
      newSet.delete(id);
    } else {
      newSet.add(id);
    }
    setSelectedTrashIds(newSet);
  };

  return (
    <Modal
      title="回收站"
      open={trashVisible}
      onCancel={() => setTrashVisible(false)}
      width={600}
      footer={
        <Space>
          <Popconfirm
            title="确定清空回收站？此操作不可撤销。"
            onConfirm={clearTrash}
            okText="清空"
            cancelText="取消"
          >
            <Button danger icon={<ClearOutlined />} disabled={trash.length === 0}>
              清空回收站
            </Button>
          </Popconfirm>
          <Button onClick={() => setTrashVisible(false)}>关闭</Button>
        </Space>
      }
    >
      {trash.length === 0 ? (
        <Empty description="回收站为空" />
      ) : (
        <>
          <Space style={{ marginBottom: 8 }}>
            <Button
              size="small"
              icon={<UndoOutlined />}
              onClick={handleRestore}
              disabled={selectedTrashIds.size === 0}
            >
              恢复选中 ({selectedTrashIds.size})
            </Button>
            <Popconfirm
              title={`确定永久删除 ${selectedTrashIds.size} 条消息？`}
              onConfirm={handlePermanentDelete}
              okText="删除"
              cancelText="取消"
            >
              <Button
                size="small"
                danger
                icon={<DeleteOutlined />}
                disabled={selectedTrashIds.size === 0}
              >
                永久删除
              </Button>
            </Popconfirm>
          </Space>
          <List
            size="small"
            dataSource={trash}
            renderItem={(item) => (
              <List.Item
                style={{
                  cursor: 'pointer',
                  background: selectedTrashIds.has(item.id) ? '#e6f4ff' : 'transparent',
                  padding: '8px 12px',
                }}
                onClick={() => toggleTrashSelection(item.id)}
              >
                <Space direction="vertical" size={2} style={{ width: '100%' }}>
                  <Text code style={{ fontSize: 12 }}>{item.command || item.kind}</Text>
                  <Text type="secondary" style={{ fontSize: 11 }}>
                    删除于 {item.deleted_at ? new Date(item.deleted_at).toLocaleString() : '未知'}
                  </Text>
                </Space>
              </List.Item>
            )}
          />
        </>
      )}
    </Modal>
  );
};