// Presentation only. Eligibility and amounts always come from the protected reader.
const messages={
 output_allocation_retirement_required:['Planning must cancel the affected eligible decision first.','يجب أن يلغي التخطيط القرار المتأثر المؤهل أولاً.'],
 output_quality_hold:['Quality changed this material. Keep it on hold until the required actions are complete.','عدلت الجودة هذه المواد. تبقى معلقة حتى اكتمال الإجراءات المطلوبة.'],
 output_handoff_pending:['Warehouse must confirm the remaining physical receipt.','يجب أن يؤكد المستودع استلام الكمية الفعلية المتبقية.'],
 output_stock_unavailable:['The source is unavailable, reserved or not physically identified. Warehouse must check the actual stock.','المصدر غير متاح أو محجوز أو غير محدد فعلياً. يجب أن يتحقق المستودع من المخزون الفعلي.'],
 output_material_committed:['Material is committed. The current physical workflow must be resolved before reconciliation.','المواد مرتبطة بالتزامات. يجب معالجة مسارها الفعلي قبل التسوية.'],
 output_revision:['This record changed. Refresh and review the latest Quality finding before trying again.','تغير السجل. حدّث العرض وراجع أحدث قرار للجودة قبل المحاولة.'],
 recordingContextChanged:['This record changed. Refresh and review the latest quantities before submitting again.','تغير السجل. حدّث العرض وراجع أحدث الكميات قبل الإرسال مجدداً.'],
 output_source_identification_required:['Confirm the actual segregated material and its storage location. A software selection alone is not traceability.','أكد المواد المفصولة فعلياً وموقع تخزينها. الاختيار البرمجي وحده لا يثبت التتبع.'],
 permissionDenied:['You do not have permission for this action. Ask the responsible department.','لا تملك صلاحية هذا الإجراء. راجع القسم المسؤول.'],
 output_reconciliation_multiple_findings:['More than one finding remains unresolved. This reconciliation is not supported here.','يوجد أكثر من قرار غير معالج. هذه التسوية غير مدعومة هنا.'],
 output_parent_held:['The source material has an unresolved Quality hold. Resolve it first.','توجد ملاحظة جودة معلقة على المواد الأصلية. عالجها أولاً.'],
 output_material_issued:['Material has already been issued. Cancellation is unavailable; preserve its physical history.','صُرفت المواد بالفعل. الإلغاء غير متاح؛ يجب الحفاظ على سجلها الفعلي.'],
 output_work_started:['Work has started. This decision cannot be cancelled here.','بدأ العمل. لا يمكن إلغاء هذا القرار هنا.'],
 output_work_committed:['Sales has a commitment to this work. Cancellation is blocked.','يوجد التزام مبيعات لهذا العمل. الإلغاء محظور.'],
 planning_locked:['The schedule is locked. Use the authorized Planning process.','الجدول مقفل. استخدم إجراء التخطيط المعتمد.'],
 planning_already_started:['The planned start has passed. Existing Planning rules block cancellation.','مر موعد البدء المخطط. تمنع قواعد التخطيط الإلغاء.'],
 output_reconciliation_release_required:['Quality must release the corrected quantities before Warehouse can reconcile them.','يجب أن تصرح الجودة بالكميات المصححة قبل تسويتها بالمستودع.']
};
export function reconciliationMessage(code,lang){return (messages[code]||['This physical state cannot be reconciled here. Keep the hold and ask Quality, Planning and Warehouse to review it.','لا يمكن تسوية هذه الحالة الفعلية هنا. أبقِ التعليق واطلب مراجعة الجودة والتخطيط والمستودع.'])[lang==='ar'?1:0];}
export function reconciliationPayload(action,{source,reason,confirmed,identification}){
 if(action?.available!==true||typeof reason!=='string'||reason.trim().length<3||reason.trim().length>2000)throw Error('output_invalid');
 if(action.mode==='UNCHANGED')return {reason:reason.trim()};
 if(confirmed!==true)throw Error('output_physical_confirmation');
 if(action.mode==='FINISHED_TO_UNFINISHED'&&action.sources?.some(s=>s.id===source))return {source_id:source,physical_confirmation:true,reason:reason.trim()};
 if(action.mode==='UNFINISHED_RECLASS'&&action.source_lot_id&&typeof action.source_location==='string'&&identification?.trim().length>=3&&identification.trim().length<=1000)return {source_lot_id:action.source_lot_id,source_location:action.source_location,identification_note:identification.trim(),physical_confirmation:true,reason:reason.trim()};
 throw Error('output_source_identification_required');
}
