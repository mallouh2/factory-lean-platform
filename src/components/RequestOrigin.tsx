import type { Row, Language, Translate } from '@/types';
import { formatTime } from './ui';
import { requestOriginLabel } from '@/utils/request-origin.mjs';
export default function RequestOrigin({request,t,lang,zone,details=false}:{request:Row|undefined;t:Translate;lang:Language;zone:string;details?:boolean}) {
  if (!request) return null;
  return <span className="delivery-context"><strong>{t(requestOriginLabel(request.request_type))}</strong>
    {details && request.request_type === 'INTERNAL_PRODUCTION' && <>
      <span dir="auto">{t('internalCreatedBy')}: {String(request.requested_by_name || t('requestCreatorNotRecorded'))}</span>
      <span dir="auto">{t('internalProductionReason')}: {String(request.notes || t('requestCreatorNotRecorded'))}</span>
      <span>{t('internalCreatedAt')}: {formatTime(request.created_at,lang,zone)}</span>
    </>}
  </span>;
}
