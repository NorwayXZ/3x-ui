import { useMemo } from 'react';
import { useMutation, useQuery } from '@tanstack/react-query';
import {
  Alert,
  Button,
  Card,
  Col,
  ConfigProvider,
  Empty,
  Layout,
  List,
  Row,
  Space,
  Spin,
  Tag,
  Typography,
  message,
} from 'antd';
import {
  CheckCircleOutlined,
  FieldTimeOutlined,
  LinkOutlined,
  PlayCircleOutlined,
  ReloadOutlined,
  StopOutlined,
} from '@ant-design/icons';

import AppSidebar from '@/layouts/AppSidebar';
import { useTheme } from '@/hooks/useTheme';
import { HttpUtil } from '@/utils';
import './AimiliPage.css';

interface AimiliUIStatus {
  host: string;
  port: number;
  proxyPort: number;
  secretPath: string;
}

interface AimiliRuntimeStatus {
  activeOpenVPNNodeId: string;
  lastCheckMessage: string;
  isConnecting: boolean;
  activeNodeLatency: string;
  localProxy: string;
  proxyOk: boolean;
  proxyIp: string;
  proxyLatencyMs: number;
  proxyError: string;
}

interface AimiliIPHistoryEntry {
  timestamp: string;
  region: string;
  nodeId: string;
  exitIp: string;
  latencyMs: number;
  trigger: string;
}

interface AimiliStatus {
  enabled: boolean;
  controlMode: string;
  serviceName: string;
  serviceState: string;
  serviceRunning: boolean;
  webReachable: boolean;
  preferredConsoleUrl: string;
  ui?: AimiliUIStatus;
  runtime?: AimiliRuntimeStatus;
  history?: AimiliIPHistoryEntry[];
  warnings?: string[];
}

interface AimiliActionResult {
  action: string;
  output?: string;
}

interface AimiliLogResult {
  lines: string[];
  source: string;
}

async function fetchAimiliStatus(): Promise<AimiliStatus> {
  const msg = await HttpUtil.get<AimiliStatus>('/panel/api/aimili/status', undefined, { silent: true });
  if (!msg.success || !msg.obj) {
    throw new Error(msg.msg || '加载住宅 IP 状态失败');
  }
  return msg.obj;
}

async function fetchAimiliLogs(): Promise<AimiliLogResult> {
  const msg = await HttpUtil.get<AimiliLogResult>('/panel/api/aimili/logs', { lines: 120 }, { silent: true });
  if (!msg.success || !msg.obj) {
    throw new Error(msg.msg || '加载日志失败');
  }
  return msg.obj;
}

function stateTagColor(running: boolean, state: string) {
  if (running) return 'green';
  if (state === 'failed') return 'red';
  if (state === 'unmanaged') return 'gold';
  return 'default';
}

function regionLabel(nodeId?: string, fallback?: string) {
  const raw = (fallback || nodeId || '').trim();
  if (!raw) return '-';
  const region = raw.includes('_') ? raw.split('_', 1)[0] : raw;
  return region.toUpperCase();
}

function formatTimestamp(value?: string) {
  if (!value) return '-';
  return value.replace(' ', '\u00A0');
}

export default function AimiliPage() {
  const { antdThemeConfig, isDark, isUltra } = useTheme();
  const [messageApi, messageContextHolder] = message.useMessage();

  const statusQuery = useQuery({
    queryKey: ['aimili', 'status'],
    queryFn: fetchAimiliStatus,
    refetchInterval: 15_000,
  });
  const logsQuery = useQuery({
    queryKey: ['aimili', 'logs'],
    queryFn: fetchAimiliLogs,
    refetchInterval: 20_000,
  });

  const actionMut = useMutation({
    mutationFn: async (action: 'start' | 'stop' | 'restart') => {
      const msg = await HttpUtil.post<AimiliActionResult>(`/panel/api/aimili/${action}`, undefined, { silent: true });
      if (!msg.success) {
        throw new Error(msg.msg || `执行 ${action} 失败`);
      }
      return msg.obj;
    },
    onSuccess: async (result) => {
      const actionName = result?.action || '操作';
      messageApi.success(`${actionName} 成功`);
      if (result?.output) {
        messageApi.info(result.output);
      }
      await Promise.all([statusQuery.refetch(), logsQuery.refetch()]);
    },
    onError: (error) => {
      const text = error instanceof Error ? error.message : String(error);
      messageApi.error(text);
    },
  });

  const pageClass = useMemo(() => {
    const classes = ['settings-page', 'aimili-page'];
    if (isDark) classes.push('is-dark');
    if (isUltra) classes.push('is-ultra');
    return classes.join(' ');
  }, [isDark, isUltra]);

  const status = statusQuery.data;
  const logs = logsQuery.data;
  const runtime = status?.runtime;
  const controlsDisabled = !status || actionMut.isPending || status.controlMode === 'none';
  const currentIP = runtime?.proxyIp || '-';
  const currentLatency = runtime?.proxyLatencyMs ? `${runtime.proxyLatencyMs} ms` : '检测中';
  const switchHistory = status?.history || [];

  return (
    <ConfigProvider theme={antdThemeConfig}>
      {messageContextHolder}
      <Layout className={pageClass}>
        <AppSidebar />

        <Layout className="content-shell">
          <Layout.Content id="content-layout" className="content-area">
            <Spin spinning={statusQuery.isLoading && !status} size="large" tip="加载住宅 IP 面板中...">
              <Space direction="vertical" size={18} style={{ width: '100%' }}>
                <Card className="aimili-hero-card">
                  <div className="aimili-hero">
                    <div>
                      <Typography.Title level={2} className="aimili-hero-title">
                        住宅IP
                      </Typography.Title>
                      <Typography.Paragraph className="aimili-hero-subtitle">
                        独立网关运行、面板统一管理、出口状态一眼可见。
                      </Typography.Paragraph>
                    </div>
                    <Space wrap>
                      <Button
                        icon={<ReloadOutlined />}
                        onClick={() => {
                          void statusQuery.refetch();
                          void logsQuery.refetch();
                        }}
                      >
                        刷新
                      </Button>
                      <Button
                        type="primary"
                        icon={<LinkOutlined />}
                        disabled={!status?.preferredConsoleUrl}
                        onClick={() => {
                          if (!status?.preferredConsoleUrl) return;
                          window.location.assign(status.preferredConsoleUrl);
                        }}
                      >
                        Open Console
                      </Button>
                    </Space>
                  </div>

                  {!status?.enabled && (
                    <Alert
                      type="warning"
                      showIcon
                      message="住宅 IP 集成尚未启用"
                      description="请在 x-ui 服务环境文件中设置 AIMILI_ENABLED=true，然后重启 x-ui。"
                    />
                  )}

                  {(status?.warnings || []).map((warning) => (
                    <Alert key={warning} type="info" showIcon message={warning} />
                  ))}

                  {statusQuery.error && (
                    <Alert
                      type="error"
                      showIcon
                      message={statusQuery.error instanceof Error ? statusQuery.error.message : '加载失败'}
                    />
                  )}
                </Card>

                <Row gutter={[18, 18]}>
                  <Col xs={24} xl={14}>
                    <Card className="aimili-card aimili-current-card">
                      <div className="aimili-current-grid">
                        <div>
                          <div className="aimili-card-label">当前出口 IP</div>
                          <div className="aimili-ip-value">{currentIP}</div>
                          <div className="aimili-inline-meta">
                            <Tag color="blue">{regionLabel(runtime?.activeOpenVPNNodeId)}</Tag>
                            {runtime?.proxyOk ? <Tag color="green">可用</Tag> : <Tag color="default">检测中</Tag>}
                            {runtime?.isConnecting ? <Tag color="gold">切换中</Tag> : <Tag color="default">已连接</Tag>}
                          </div>
                        </div>
                        <div className="aimili-kpi-strip">
                          <div className="aimili-kpi">
                            <span className="aimili-kpi-label">节点</span>
                            <span className="aimili-kpi-value">{runtime?.activeOpenVPNNodeId || '-'}</span>
                          </div>
                          <div className="aimili-kpi">
                            <span className="aimili-kpi-label">代理延迟</span>
                            <span className="aimili-kpi-value">{currentLatency}</span>
                          </div>
                          <div className="aimili-kpi">
                            <span className="aimili-kpi-label">节点延迟</span>
                            <span className="aimili-kpi-value">{runtime?.activeNodeLatency || '-'}</span>
                          </div>
                          <div className="aimili-kpi">
                            <span className="aimili-kpi-label">本地代理</span>
                            <span className="aimili-kpi-value">{status?.ui ? `127.0.0.1:${status.ui.proxyPort}` : '-'}</span>
                          </div>
                        </div>
                      </div>
                    </Card>
                  </Col>

                  <Col xs={24} xl={10}>
                    <Card
                      className="aimili-card"
                      title="服务控制"
                      extra={<Tag color={stateTagColor(Boolean(status?.serviceRunning), status?.serviceState || '')}>{status?.serviceState || 'unknown'}</Tag>}
                    >
                      <div className="aimili-service-stack">
                        <div className="aimili-status-row">
                          <span className="aimili-card-label">服务状态</span>
                          <span className="aimili-service-text">
                            <CheckCircleOutlined /> {status?.serviceRunning ? '运行中' : '已停止'}
                          </span>
                        </div>
                        <div className="aimili-status-row">
                          <span className="aimili-card-label">控制台状态</span>
                          <span className="aimili-service-text">
                            {status?.webReachable ? '已就绪' : '未就绪'}
                          </span>
                        </div>
                        <div className="aimili-status-row">
                          <span className="aimili-card-label">最近状态</span>
                          <span className="aimili-service-muted">{runtime?.lastCheckMessage || '等待首次检测'}</span>
                        </div>
                        <Space wrap>
                          <Button
                            icon={<PlayCircleOutlined />}
                            disabled={controlsDisabled}
                            loading={actionMut.isPending && actionMut.variables === 'start'}
                            onClick={() => actionMut.mutate('start')}
                          >
                            启动
                          </Button>
                          <Button
                            icon={<StopOutlined />}
                            disabled={controlsDisabled}
                            loading={actionMut.isPending && actionMut.variables === 'stop'}
                            onClick={() => actionMut.mutate('stop')}
                          >
                            停止
                          </Button>
                          <Button
                            icon={<ReloadOutlined />}
                            disabled={controlsDisabled}
                            loading={actionMut.isPending && actionMut.variables === 'restart'}
                            onClick={() => actionMut.mutate('restart')}
                          >
                            重启
                          </Button>
                        </Space>
                      </div>
                    </Card>
                  </Col>
                </Row>

                <Row gutter={[18, 18]}>
                  <Col xs={24} xl={10}>
                    <Card className="aimili-card" title="IP 切换记录" extra={<FieldTimeOutlined />}>
                      {switchHistory.length ? (
                        <List
                          dataSource={switchHistory}
                          className="aimili-history-list"
                          renderItem={(item) => (
                            <List.Item className="aimili-history-item">
                              <div className="aimili-history-head">
                                <Space wrap size={8}>
                                  <Tag color="blue">{item.region || regionLabel(item.nodeId)}</Tag>
                                  <Typography.Text strong>{item.exitIp}</Typography.Text>
                                  <Tag color={item.trigger === '自动切换' ? 'gold' : 'green'}>{item.trigger}</Tag>
                                </Space>
                                <Typography.Text type="secondary">{formatTimestamp(item.timestamp)}</Typography.Text>
                              </div>
                              <div className="aimili-history-body">
                                <span>{item.nodeId}</span>
                                <span>{item.latencyMs ? `${item.latencyMs} ms` : '-'}</span>
                              </div>
                            </List.Item>
                          )}
                        />
                      ) : (
                        <Empty image={Empty.PRESENTED_IMAGE_SIMPLE} description="还没有可展示的切换记录" />
                      )}
                    </Card>
                  </Col>

                  <Col xs={24} xl={14}>
                    <Card
                      className="aimili-card"
                      title={`实时日志${logs?.source ? ` (${logs.source})` : ''}`}
                      extra={
                        <Button size="small" onClick={() => void logsQuery.refetch()} icon={<ReloadOutlined />}>
                          刷新
                        </Button>
                      }
                    >
                      {logsQuery.error ? (
                        <Alert
                          type="error"
                          showIcon
                          message={logsQuery.error instanceof Error ? logsQuery.error.message : '日志加载失败'}
                        />
                      ) : logs?.lines?.length ? (
                        <Typography.Paragraph className="aimili-log-pane">
                          {logs.lines.join('\n')}
                        </Typography.Paragraph>
                      ) : (
                        <Empty image={Empty.PRESENTED_IMAGE_SIMPLE} description="暂无日志" />
                      )}
                    </Card>
                  </Col>
                </Row>
              </Space>
            </Spin>
          </Layout.Content>
        </Layout>
      </Layout>
    </ConfigProvider>
  );
}
