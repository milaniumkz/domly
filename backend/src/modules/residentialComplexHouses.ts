import type {AddressSuggestion} from './integrations';

type Point = {lat: number; lng: number};
function inside(point: Point, polygon: Point[]) {
  let result = false;
  for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    const a = polygon[i], b = polygon[j];
    if ((a.lat > point.lat) !== (b.lat > point.lat)
      && point.lng < (b.lng - a.lng) * (point.lat - a.lat) / (b.lat - a.lat) + a.lng) result = !result;
  }
  return result;
}

/** Only addresses inside the actual complex boundary; a bounding box is not membership. */
export function residentialComplexHouses(complex: AddressSuggestion, data: any): AddressSuggestion[] {
  const elements: any[] = Array.isArray(data?.elements) ? data.elements : [];
  const nodes = new Map<number, Point>(elements.filter(e => e.type === 'node').map(e => [e.id, {lat: e.lat, lng: e.lon}]));
  const boundary = elements.find(e => e.type === 'way' && e.id === (complex.raw as any)?.osm_id);
  const polygon: Point[] = (boundary?.nodes ?? []).map((id: number) => nodes.get(id)).filter(Boolean);
  if (polygon.length < 4 || boundary.nodes[0] !== boundary.nodes[boundary.nodes.length - 1]) return [];
  const result = new Map<string, AddressSuggestion>();
  for (const element of elements) {
    const tags = element.tags ?? {};
    const street = tags['addr:street:ru'] ?? tags['addr:street'] ?? tags['addr:place'];
    const house = tags['addr:housenumber'];
    if (!street || !house) continue;
    const points: Point[] = element.type === 'node' ? [nodes.get(element.id)!]
      : (element.nodes ?? []).map((id: number) => nodes.get(id)).filter(Boolean);
    if (!points.length) continue;
    const center = {lat: points.reduce((s,p) => s+p.lat,0)/points.length, lng: points.reduce((s,p) => s+p.lng,0)/points.length};
    if (!inside(center, polygon)) continue;
    result.set(`${street}|${house}`, {source:'osm', label:`${complex.residentialComplex}, ${street}, ${house}`,
      city:complex.city, street, house, residentialComplex:complex.residentialComplex,
      lat:center.lat,lng:center.lng,distanceKm:null,raw:element});
  }
  return [...result.values()].sort((a,b) => a.label.localeCompare(b.label,'ru',{numeric:true}));
}
