import { useEffect } from 'react';
import { useLocation } from 'react-router-dom';
import { useTranslation } from 'react-i18next';

const TITLE_KEYS: Record<string, { key: string; fallback: string }> = {
  '/': { key: 'menu.dashboard', fallback: 'Dashboard' },
  '/inbounds': { key: 'menu.inbounds', fallback: 'Inbounds' },
  '/clients': { key: 'menu.clients', fallback: 'Clients' },
  '/groups': { key: 'menu.groups', fallback: 'Groups' },
  '/nodes': { key: 'menu.nodes', fallback: 'Nodes' },
  '/aimili': { key: 'menu.aimili', fallback: 'Residential IP' },
  '/hosts': { key: 'menu.hosts', fallback: 'Hosts' },
  '/settings': { key: 'menu.settings', fallback: 'Settings' },
  '/xray': { key: 'menu.xray', fallback: 'Xray Config' },
  '/outbound': { key: 'menu.outbounds', fallback: 'Outbounds' },
  '/routing': { key: 'menu.routing', fallback: 'Routing' },
  '/api-docs': { key: 'menu.apiDocs', fallback: 'API Docs' },
};

export function usePageTitle() {
  const { pathname } = useLocation();
  const { t } = useTranslation();

  useEffect(() => {
    const meta = TITLE_KEYS[pathname];
    const translated = meta ? t(meta.key) : '3X-UI';
    const title = meta ? (translated === meta.key ? meta.fallback : translated) : '3X-UI';
    const host = window.location.hostname;
    document.title = host ? `${host} - ${title}` : title;
  }, [pathname, t]);
}
