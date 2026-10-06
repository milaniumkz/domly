const API_BASE = process.env.REACT_APP_API_BASE ?? 'http://localhost:8080';

export async function getAddons() {
  const response = await fetch(`${API_BASE}/addons`);
  if (!response.ok) throw new Error('Failed to load addons');
  return response.json();
}

export async function calculateCustomPackage(payload: unknown) {
  const response = await fetch(`${API_BASE}/custom-package/calculate`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });
  if (!response.ok) throw new Error('Failed to calculate custom package');
  return response.json();
}

export async function confirmCustomPackage(draftId: string) {
  const response = await fetch(`${API_BASE}/custom-package/confirm`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ draftId }),
  });
  if (!response.ok) throw new Error('Failed to confirm custom package');
  return response.json();
}

export async function checkoutCustomPackage(packageId: string) {
  const response = await fetch(`${API_BASE}/custom-package/checkout`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ packageId }),
  });
  if (!response.ok) throw new Error('Failed to checkout custom package');
  return response.json();
}
