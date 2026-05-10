import { VariableWindow } from './VariableWindow';
import { InfoWindow } from './InfoWindow';

export function Sidebar() {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%', background: '#fafafa' }}>
      {/* 上半部分：变量窗口 */}
      <div style={{ flex: 1, overflow: 'hidden', borderBottom: '1px solid #e8e8e8' }}>
        <VariableWindow />
      </div>
      {/* 下半部分：信息窗口 */}
      <div style={{ flex: 1, overflow: 'hidden' }}>
        <InfoWindow />
      </div>
    </div>
  );
}
