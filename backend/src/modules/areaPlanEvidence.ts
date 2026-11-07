/** Join the plan actually reviewed by the bot, scoped to this customer and request. */
export const areaPlanEvidenceJoin = `LEFT JOIN LATERAL (
  SELECT e.evidence->>'documentUrl' AS document_url, e.evidence,
         e.created_at AS verified_at
  FROM bot_area_events e
  WHERE e.customer_id=q.customer_id AND e.result->>'qualityCheckId'=q.id::text
    AND e.evidence->>'documentType'='technical_plan'
    AND e.evidence->>'documentUrl' LIKE 'https://%'
  ORDER BY e.created_at DESC,e.event_id DESC LIMIT 1
) bot_plan ON TRUE`;

export const areaPlanEvidenceColumns = `
  COALESCE(bot_plan.document_url,f.public_url) AS document_url,
  COALESCE(bot_plan.document_url,f.public_url) AS "areaTechnicalPlanUrl",
  f.public_url AS uploaded_document_url,
  bot_plan.document_url AS bot_document_url,
  bot_plan.evidence AS bot_evidence,
  bot_plan.verified_at AS bot_verified_at`;
