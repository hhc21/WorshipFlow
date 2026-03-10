'use client';

import {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState
} from 'react';
import type { PointerEvent as ReactPointerEvent } from 'react';

const PROTOCOL_VERSION = 'v1';
const SCHEMA_VERSION = 'relative-v1';

type JsonScalar = string | number | boolean | null;
type JsonValue = JsonScalar | JsonObject | JsonValue[];
type JsonObject = { [key: string]: JsonValue };

type EditingLayer = 'private' | 'shared';

interface Envelope {
  type: string;
  version: string;
  requestId: string;
  payload: JsonObject;
}

interface StrokePoint {
  x: number;
  y: number;
}

interface Stroke {
  schemaVersion: string;
  colorValue: number;
  width: number;
  points: StrokePoint[];
}

interface InitPayload {
  teamId: string;
  projectId: string;
  currentSongId: string;
  currentKeyText: string;
  scoreImageUrl: string;
  idToken: string;
  canEdit: boolean;
  editingLayer: EditingLayer;
  willReadFrequently: boolean;
  privateStrokes: Stroke[];
  sharedStrokes: Stroke[];
}

function isJsonObject(value: JsonValue | undefined): value is JsonObject {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function parseJsonString(raw: string): JsonValue | null {
  try {
    const parsed = JSON.parse(raw) as JsonValue;
    return parsed;
  } catch {
    return null;
  }
}

function clampFixed8(value: number): number {
  const clamped = Math.min(1, Math.max(0, value));
  return Math.round(clamped * 1e8) / 1e8;
}

function toEditingLayer(value: string): EditingLayer {
  return value === 'shared' ? 'shared' : 'private';
}

function toText(value: JsonValue | undefined): string {
  return typeof value === 'string' ? value : '';
}

function toBool(value: JsonValue | undefined): boolean {
  return value === true;
}

function toNumber(value: JsonValue | undefined, fallback: number): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    return fallback;
  }
  return value;
}

function resolveHostOrigin(): string {
  if (typeof window === 'undefined') return '';
  const queryOrigin = window.location.search
    ? new URLSearchParams(window.location.search).get('hostOrigin') ?? ''
    : '';
  const normalizedQueryOrigin = normalizeOrigin(queryOrigin);
  if (normalizedQueryOrigin.length > 0) {
    return normalizedQueryOrigin;
  }
  const referrer = document.referrer ?? '';
  if (referrer.length === 0) return '';
  try {
    return normalizeOrigin(new URL(referrer).origin);
  } catch {
    return '';
  }
}

function normalizeOrigin(raw: string): string {
  const trimmed = raw.trim();
  if (trimmed.length === 0) return '';
  try {
    const parsed = new URL(trimmed);
    if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
      return '';
    }
    return parsed.origin;
  } catch {
    return '';
  }
}

function toPointList(value: JsonValue | undefined): StrokePoint[] {
  if (!Array.isArray(value)) return [];
  const points: StrokePoint[] = [];
  for (const item of value) {
    if (!isJsonObject(item)) continue;
    points.push({
      x: clampFixed8(toNumber(item.x, 0)),
      y: clampFixed8(toNumber(item.y, 0))
    });
  }
  return points;
}

function toStrokeList(value: JsonValue | undefined, fallbackColor: number): Stroke[] {
  if (!Array.isArray(value)) return [];
  const out: Stroke[] = [];
  for (const item of value) {
    if (!isJsonObject(item)) continue;
    const points = toPointList(item.points);
    if (points.length === 0) continue;
    out.push({
      schemaVersion: SCHEMA_VERSION,
      colorValue: Math.trunc(toNumber(item.colorValue, fallbackColor)),
      width: toNumber(item.width, 2.8),
      points
    });
  }
  return out;
}

function parseEnvelope(raw: JsonValue): Envelope | null {
  const parsedValue = typeof raw === 'string' ? parseJsonString(raw) : raw;
  if (!isJsonObject(parsedValue)) return null;
  const type = toText(parsedValue.type);
  const version = toText(parsedValue.version);
  const requestId = toText(parsedValue.requestId);
  const payload = isJsonObject(parsedValue.payload)
    ? parsedValue.payload
    : {};
  if (type.length === 0) return null;
  return {
    type,
    version,
    requestId,
    payload
  };
}

function parseInitPayload(payload: JsonObject): InitPayload {
  const editingLayer = toEditingLayer(toText(payload.editingLayer));
  return {
    teamId: toText(payload.teamId),
    projectId: toText(payload.projectId),
    currentSongId: toText(payload.currentSongId),
    currentKeyText: toText(payload.currentKeyText),
    scoreImageUrl: toText(payload.scoreImageUrl),
    idToken: toText(payload.idToken),
    canEdit: toBool(payload.canEdit),
    editingLayer,
    willReadFrequently: toBool(payload.willReadFrequently),
    privateStrokes: toStrokeList(payload.privateStrokes, 0xffd32f2f),
    sharedStrokes: toStrokeList(payload.sharedStrokes, 0xff1976d2)
  };
}

function toRgbaColor(colorValue: number): string {
  const alpha = ((colorValue >> 24) & 0xff) / 255;
  const red = (colorValue >> 16) & 0xff;
  const green = (colorValue >> 8) & 0xff;
  const blue = colorValue & 0xff;
  return `rgba(${red}, ${green}, ${blue}, ${alpha.toFixed(4)})`;
}

function strokeHit(stroke: Stroke, point: StrokePoint): boolean {
  const radius = Math.min(0.04, Math.max(0.012, 0.018 + stroke.width / 450));
  const radiusSquared = radius * radius;
  for (const strokePoint of stroke.points) {
    const dx = strokePoint.x - point.x;
    const dy = strokePoint.y - point.y;
    if (dx * dx + dy * dy <= radiusSquared) {
      return true;
    }
  }
  return false;
}

function serializeStrokes(strokes: Stroke[]): JsonValue[] {
  return strokes.map((stroke) => ({
    schemaVersion: SCHEMA_VERSION,
    colorValue: stroke.colorValue,
    width: stroke.width,
    points: stroke.points.map((point) => ({
      x: clampFixed8(point.x),
      y: clampFixed8(point.y)
    }))
  }));
}

export default function Page() {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const privateStrokesRef = useRef<Stroke[]>([]);
  const sharedStrokesRef = useRef<Stroke[]>([]);
  const activeStrokeRef = useRef<Stroke | null>(null);
  const dirtyRef = useRef(false);
  const requestSeedRef = useRef(0);

  const [initPayload, setInitPayload] = useState<InitPayload | null>(null);
  const [editingLayer, setEditingLayer] = useState<EditingLayer>('private');
  const [eraserEnabled, setEraserEnabled] = useState(false);
  const [dirty, setDirty] = useState(false);
  const [scoreLoadError, setScoreLoadError] = useState('');
  const [revision, setRevision] = useState(0);
  const hostOrigin = useMemo(() => resolveHostOrigin(), []);

  const canEdit = initPayload?.canEdit ?? false;
  const willReadFrequently = initPayload?.willReadFrequently ?? false;

  const postEnvelope = useCallback((type: string, payload: JsonObject) => {
    if (hostOrigin.length === 0) return;
    if (window.parent === window) return;
    const requestId = `${type}-${Date.now()}-${requestSeedRef.current++}`;
    const envelope: Envelope = {
      type,
      version: PROTOCOL_VERSION,
      requestId,
      payload
    };
    window.parent.postMessage(envelope, hostOrigin);
  }, [hostOrigin]);

  const postCommit = useCallback(() => {
    postEnvelope('ink-commit', {
      editingLayer,
      privateStrokes: serializeStrokes(privateStrokesRef.current),
      sharedStrokes: serializeStrokes(sharedStrokesRef.current)
    });
  }, [editingLayer, postEnvelope]);

  const markDirty = useCallback(() => {
    if (!dirtyRef.current) {
      dirtyRef.current = true;
      setDirty(true);
      postEnvelope('ink-dirty', { dirty: true });
    }
  }, [postEnvelope]);

  const normalizePointer = useCallback(
    (event: ReactPointerEvent<HTMLCanvasElement>): StrokePoint | null => {
      const canvas = canvasRef.current;
      if (canvas === null) return null;
      const rect = canvas.getBoundingClientRect();
      if (rect.width <= 0 || rect.height <= 0) return null;
      return {
        x: clampFixed8((event.clientX - rect.left) / rect.width),
        y: clampFixed8((event.clientY - rect.top) / rect.height)
      };
    },
    []
  );

  const appendStrokeToLayer = useCallback(
    (stroke: Stroke) => {
      if (editingLayer === 'shared') {
        sharedStrokesRef.current = [...sharedStrokesRef.current, stroke];
      } else {
        privateStrokesRef.current = [...privateStrokesRef.current, stroke];
      }
    },
    [editingLayer]
  );

  const eraseAt = useCallback(
    (point: StrokePoint) => {
      const beforePrivate = privateStrokesRef.current.length;
      const beforeShared = sharedStrokesRef.current.length;
      if (editingLayer === 'shared') {
        sharedStrokesRef.current = sharedStrokesRef.current.filter(
          (stroke) => !strokeHit(stroke, point)
        );
      } else {
        privateStrokesRef.current = privateStrokesRef.current.filter(
          (stroke) => !strokeHit(stroke, point)
        );
      }
      const changed =
        beforePrivate !== privateStrokesRef.current.length ||
        beforeShared !== sharedStrokesRef.current.length;
      if (!changed) return;
      markDirty();
      postCommit();
      setRevision((value) => value + 1);
    },
    [editingLayer, markDirty, postCommit]
  );

  const handlePointerDown = useCallback(
    (event: ReactPointerEvent<HTMLCanvasElement>) => {
      if (!canEdit) return;
      const point = normalizePointer(event);
      if (point === null) return;
      event.currentTarget.setPointerCapture(event.pointerId);
      if (eraserEnabled) {
        eraseAt(point);
        return;
      }
      const colorValue = editingLayer === 'shared' ? 0xff1976d2 : 0xffd32f2f;
      activeStrokeRef.current = {
        schemaVersion: SCHEMA_VERSION,
        colorValue,
        width: 2.8,
        points: [point]
      };
      setRevision((value) => value + 1);
    },
    [canEdit, editingLayer, eraserEnabled, eraseAt, normalizePointer]
  );

  const handlePointerMove = useCallback(
    (event: ReactPointerEvent<HTMLCanvasElement>) => {
      if (!canEdit) return;
      const point = normalizePointer(event);
      if (point === null) return;
      if (eraserEnabled) {
        eraseAt(point);
        return;
      }
      const activeStroke = activeStrokeRef.current;
      if (activeStroke === null) return;
      activeStroke.points = [...activeStroke.points, point];
      setRevision((value) => value + 1);
    },
    [canEdit, eraserEnabled, eraseAt, normalizePointer]
  );

  const finishActiveStroke = useCallback(() => {
    const activeStroke = activeStrokeRef.current;
    if (activeStroke === null) return;
    activeStrokeRef.current = null;
    if (activeStroke.points.length > 0) {
      appendStrokeToLayer(activeStroke);
      markDirty();
      postCommit();
    }
    setRevision((value) => value + 1);
  }, [appendStrokeToLayer, markDirty, postCommit]);

  const undoStroke = useCallback(() => {
    if (!canEdit) return;
    activeStrokeRef.current = null;
    if (editingLayer === 'shared') {
      if (sharedStrokesRef.current.length === 0) return;
      sharedStrokesRef.current = sharedStrokesRef.current.slice(0, -1);
    } else {
      if (privateStrokesRef.current.length === 0) return;
      privateStrokesRef.current = privateStrokesRef.current.slice(0, -1);
    }
    markDirty();
    postCommit();
    setRevision((value) => value + 1);
  }, [canEdit, editingLayer, markDirty, postCommit]);

  const clearLayer = useCallback(() => {
    if (!canEdit) return;
    activeStrokeRef.current = null;
    if (editingLayer === 'shared') {
      if (sharedStrokesRef.current.length === 0) return;
      sharedStrokesRef.current = [];
    } else {
      if (privateStrokesRef.current.length === 0) return;
      privateStrokesRef.current = [];
    }
    markDirty();
    postCommit();
    setRevision((value) => value + 1);
  }, [canEdit, editingLayer, markDirty, postCommit]);

  useEffect(() => {
    const messageHandler = (event: MessageEvent) => {
      if (hostOrigin.length > 0 && event.origin !== hostOrigin) {
        return;
      }
      const envelope = parseEnvelope(event.data as JsonValue);
      if (envelope === null) return;
      if (envelope.version !== PROTOCOL_VERSION) return;

      if (envelope.type === 'host-init') {
        const nextInit = parseInitPayload(envelope.payload);
        setInitPayload(nextInit);
        setEditingLayer(nextInit.editingLayer);
        privateStrokesRef.current = nextInit.privateStrokes;
        sharedStrokesRef.current = nextInit.sharedStrokes;
        activeStrokeRef.current = null;
        dirtyRef.current = false;
        setDirty(false);
        setScoreLoadError('');
        setRevision((value) => value + 1);
        postEnvelope('init-applied', {
          projectId: nextInit.projectId,
          teamId: nextInit.teamId,
          editingLayer: nextInit.editingLayer,
          ready: true
        });
        return;
      }

      if (envelope.type === 'token-refresh') {
        const token = toText(envelope.payload.idToken);
        if (token.length === 0) return;
        setInitPayload((prev) => {
          if (prev === null) return prev;
          return {
            ...prev,
            idToken: token
          };
        });
        return;
      }

      if (envelope.type === 'ink-synced') {
        dirtyRef.current = false;
        setDirty(false);
        postEnvelope('ink-synced', { dirty: false });
      }
    };

    postEnvelope('viewer-ready', {
      viewerVersion: 'next-livecue-v1',
      sketchSchemaVersion: SCHEMA_VERSION
    });
    window.addEventListener('message', messageHandler);
    return () => {
      window.removeEventListener('message', messageHandler);
    };
  }, [hostOrigin, postEnvelope]);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (canvas === null) return;
    const rect = canvas.getBoundingClientRect();
    const width = Math.max(1, Math.floor(rect.width));
    const height = Math.max(1, Math.floor(rect.height));
    if (canvas.width !== width) canvas.width = width;
    if (canvas.height !== height) canvas.height = height;

    const contextSettings: CanvasRenderingContext2DSettings = willReadFrequently
      ? { willReadFrequently: true }
      : {};
    const context = canvas.getContext('2d', contextSettings);
    if (context === null) return;

    context.clearRect(0, 0, canvas.width, canvas.height);

    const drawStroke = (stroke: Stroke) => {
      if (stroke.points.length === 0) return;
      context.strokeStyle = toRgbaColor(stroke.colorValue);
      context.fillStyle = toRgbaColor(stroke.colorValue);
      context.lineWidth = stroke.width;
      context.lineCap = 'round';
      context.lineJoin = 'round';
      if (stroke.points.length === 1) {
        const point = stroke.points[0];
        context.beginPath();
        context.arc(
          point.x * canvas.width,
          point.y * canvas.height,
          stroke.width * 0.55,
          0,
          Math.PI * 2
        );
        context.fill();
        return;
      }
      context.beginPath();
      const first = stroke.points[0];
      context.moveTo(first.x * canvas.width, first.y * canvas.height);
      for (let i = 1; i < stroke.points.length; i += 1) {
        const point = stroke.points[i];
        context.lineTo(point.x * canvas.width, point.y * canvas.height);
      }
      context.stroke();
    };

    for (const stroke of privateStrokesRef.current) {
      drawStroke(stroke);
    }
    for (const stroke of sharedStrokesRef.current) {
      drawStroke(stroke);
    }
    if (activeStrokeRef.current !== null) {
      drawStroke(activeStrokeRef.current);
    }
  }, [revision, willReadFrequently]);

  useEffect(() => {
    const resizeHandler = () => {
      setRevision((value) => value + 1);
    };
    window.addEventListener('resize', resizeHandler);
    return () => {
      window.removeEventListener('resize', resizeHandler);
    };
  }, []);

  const statusLabel = useMemo(() => {
    if (initPayload === null) return 'host-init 대기';
    if (dirty) return '미저장 필기 있음';
    return '동기화 완료';
  }, [dirty, initPayload]);

  const handleImageLoadError = useCallback(() => {
    const url = initPayload?.scoreImageUrl ?? '';
    setScoreLoadError('악보 이미지 로드 실패');
    postEnvelope('asset-cors-failed', {
      code: 'image-load-failed',
      message: 'Score image failed to load in viewer',
      url
    });
  }, [initPayload?.scoreImageUrl, postEnvelope]);

  return (
    <main className="viewer-root">
      <div className="layer score-layer">
        {initPayload?.scoreImageUrl ? (
          <img
            alt="score"
            className="score-image"
            crossOrigin="anonymous"
            src={initPayload.scoreImageUrl}
            onError={handleImageLoadError}
            onLoad={() => setScoreLoadError('')}
          />
        ) : null}
      </div>

      <div className="layer ink-layer">
        <canvas
          ref={canvasRef}
          className="ink-canvas"
          onPointerDown={handlePointerDown}
          onPointerMove={handlePointerMove}
          onPointerUp={finishActiveStroke}
          onPointerCancel={finishActiveStroke}
          onPointerLeave={finishActiveStroke}
        />
      </div>

      <div className="layer ui-layer">
        <div className="panel">
          <div className="panel-row">
            <span className="chip">{statusLabel}</span>
            <span className="chip">
              willReadFrequently: {willReadFrequently ? 'enabled' : 'disabled'}
            </span>
            <span className="chip">편집 레이어: {editingLayer}</span>
            <span className="chip">
              key: {initPayload?.currentKeyText || '-'}
            </span>
          </div>
          {scoreLoadError.length > 0 ? <div className="alert">{scoreLoadError}</div> : null}
        </div>

        <div className="panel">
          <div className="panel-row">
            <button
              type="button"
              className={`button ${editingLayer === 'private' ? 'active' : ''}`}
              disabled={!canEdit}
              onClick={() => setEditingLayer('private')}
            >
              개인 레이어
            </button>
            <button
              type="button"
              className={`button ${editingLayer === 'shared' ? 'active' : ''}`}
              disabled={!canEdit}
              onClick={() => setEditingLayer('shared')}
            >
              공유 레이어
            </button>
            <button
              type="button"
              className={`button ${eraserEnabled ? 'active' : ''}`}
              disabled={!canEdit}
              onClick={() => setEraserEnabled((value) => !value)}
            >
              {eraserEnabled ? '지우개' : '펜'}
            </button>
            <button
              type="button"
              className="button"
              disabled={!canEdit}
              onClick={undoStroke}
            >
              되돌리기
            </button>
            <button
              type="button"
              className="button"
              disabled={!canEdit}
              onClick={clearLayer}
            >
              레이어 지우기
            </button>
          </div>
        </div>
      </div>
    </main>
  );
}
