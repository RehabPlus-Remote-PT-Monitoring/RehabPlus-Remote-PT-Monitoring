<?php

namespace App\Services\Patient;

use App\Services\Firebase\FirebaseException;
use App\Services\Firebase\FirestoreBytes;
use App\Services\Firebase\FirestoreClient;
use Illuminate\Support\Facades\Log;

/**
 * Movement replays: the pose points the app saved with a session
 * (patients/{uid}/sessions/{id}/replay/{meta|c000..c019}, see API_CONTRACT.md
 * and docs/superpowers/specs/2026-11-15-movement-replay-design.md).
 *
 * The patient's phone writes these documents, so everything is untrusted:
 * meta fields are coerced to safe ranges and every chunk is checked against
 * the byte layout before it reaches the page. The frames themselves are
 * decoded in the browser (resources/js/replay-format.js); the server only
 * checks sizes, so a chunk the decoder could misread never gets there.
 *
 * Callers check who may see the patient (PatientService::find) first: the
 * service account bypasses Firestore rules.
 */
class ReplayService
{
    /** uint32 time + uint16 angle + 33 x (uint16 x, uint16 y, uint8 confidence). */
    public const FRAME_BYTES = 171;

    public const FRAMES_PER_CHUNK = 300;

    public const MAX_CHUNKS = 20;

    public const MAX_EVENTS = 200;

    public const EVENT_KINDS = ['counted', 'rejected', 'hold'];

    public function __construct(private FirestoreClient $db) {}

    /**
     * One session plus its replay, for the replay page.
     *
     * Returns null when the session doesn't exist (the page 404s). A session
     * read failure throws like every other page read (the exception handler
     * shows the friendly error page), but the replay part never throws: a
     * missing, unreadable or malformed replay comes back as replay => null
     * and the reason is logged.
     *
     * @return array{session: array, replay: ?array}|null
     */
    public function forSession(string $patientUid, string $sessionId): ?array
    {
        if (! FirestoreClient::isValidId($patientUid) || ! FirestoreClient::isValidId($sessionId)) {
            return null;
        }

        $sessionPath = "patients/{$patientUid}/sessions/{$sessionId}";

        // Both reads in one parallel round trip. All 20 possible chunk ids are
        // requested with meta (missing ones cost nothing), so the replay needs
        // no second round after meta says how many chunks there are.
        $loaded = $this->db->concurrently([
            'session' => fn () => $this->db->get($sessionPath),
            'replay' => fn () => $this->readReplayDocs($sessionPath),
        ]);

        if ($loaded['session'] === null) {
            return null;
        }

        $session = PatientProgress::presentSession($loaded['session']);
        $replay = $loaded['replay'] === null ? null : $this->build($sessionPath, $loaded['replay'], $session['hasReplay']);

        return ['session' => $session, 'replay' => $replay];
    }

    /**
     * meta + c000..c019 keyed by doc id, or null when the read failed.
     * Caught here so a replay problem can't fail the session read beside it.
     *
     * @return array<string, ?array>|null
     */
    private function readReplayDocs(string $sessionPath): ?array
    {
        $ids = ['meta', ...array_map(fn (int $i) => self::chunkId($i), range(0, self::MAX_CHUNKS - 1))];

        try {
            $docs = $this->db->getMany(array_map(fn (string $id) => "{$sessionPath}/replay/{$id}", $ids));
        } catch (FirebaseException $e) {
            $this->unavailable($sessionPath, 'read failed', ['error' => $e->getMessage()]);

            return null;
        }

        return array_combine($ids, array_values($docs));
    }

    /** Validated replay for the page, or null (reason logged). */
    private function build(string $sessionPath, array $docs, bool $expected): ?array
    {
        if ($docs['meta'] === null) {
            // Normal when the patient turned replays off (no hasReplay); only
            // a session that says it has one but doesn't is worth a warning.
            $expected
                ? $this->unavailable($sessionPath, 'no meta document')
                : Log::info('replay.none', ['session' => $sessionPath]);

            return null;
        }

        $meta = self::coerceMeta($docs['meta']);
        if (is_string($meta)) {
            $this->unavailable($sessionPath, $meta);

            return null;
        }

        $chunks = [];
        $frames = 0;
        for ($i = 0; $i < $meta['chunkCount']; $i++) {
            $problem = self::chunkProblem($docs[self::chunkId($i)], $i);
            if ($problem !== null) {
                // Frames must be contiguous, so everything after a bad chunk is
                // dropped too; the page plays what came before it.
                Log::warning('replay.chunk_skipped', ['session' => $sessionPath, 'chunk' => self::chunkId($i), 'reason' => $problem]);
                break;
            }
            $chunk = $docs[self::chunkId($i)];
            $chunks[] = $chunk['data']->toBase64();
            $frames += $chunk['frames'];
        }

        if ($chunks === []) {
            $this->unavailable($sessionPath, 'no readable chunks');

            return null;
        }

        return $meta + [
            'chunks' => $chunks,
            'frameTotal' => $frames,
            'partial' => count($chunks) < $meta['chunkCount'],
        ];
    }

    /**
     * Meta in the shape the player expects, or the reason it can't be used.
     * Only version and chunkCount are hard requirements (without them the
     * chunks can't be read safely); everything else falls back to a default.
     */
    public static function coerceMeta(array $meta): array|string
    {
        if (($meta['version'] ?? null) !== 1) {
            return 'unsupported version';
        }
        $chunkCount = $meta['chunkCount'] ?? null;
        if (! is_int($chunkCount) || $chunkCount < 1 || $chunkCount > self::MAX_CHUNKS) {
            return 'bad chunkCount';
        }

        $fps = $meta['fps'] ?? null;
        $aspect = $meta['aspect'] ?? null;
        $aspect = is_int($aspect) || (is_float($aspect) && is_finite($aspect)) ? (float) $aspect : 0.5625;
        $duration = $meta['durationMs'] ?? null;
        $label = $meta['angleLabel'] ?? null;

        return [
            'fps' => is_int($fps) ? max(1, min(10, $fps)) : 10,
            'chunkCount' => $chunkCount,
            'durationMs' => is_int($duration) && $duration >= 0 ? $duration : 0,
            'truncated' => ($meta['truncated'] ?? false) === true,
            // 9:16 (portrait phone) when missing; clamped so a silly value
            // can't squash the figure into a line.
            'aspect' => max(0.2, min(5.0, $aspect)),
            'mirrored' => ($meta['mirrored'] ?? false) === true,
            'angleLabel' => is_string($label) && trim($label) !== '' ? mb_substr(trim($label), 0, 60) : 'Angle',
            'events' => self::coerceEvents($meta['events'] ?? null),
        ];
    }

    /**
     * Rep / hold events: only maps with an int time >= 0 and a known kind,
     * note cut to 120 characters, at most 200, in time order.
     *
     * @return array<int, array{t: int, kind: string, note: string}>
     */
    public static function coerceEvents(mixed $events): array
    {
        if (! is_array($events)) {
            return [];
        }

        $kept = [];
        foreach ($events as $event) {
            if (count($kept) >= self::MAX_EVENTS) {
                break;
            }
            if (! is_array($event) || array_is_list($event)) {
                continue;
            }
            $t = $event['t'] ?? null;
            $kind = $event['kind'] ?? null;
            if (! is_int($t) || $t < 0 || ! in_array($kind, self::EVENT_KINDS, true)) {
                continue;
            }
            $note = $event['note'] ?? '';
            $kept[] = ['t' => $t, 'kind' => $kind, 'note' => is_string($note) ? mb_substr($note, 0, 120) : ''];
        }

        usort($kept, fn ($a, $b) => $a['t'] <=> $b['t']);

        return $kept;
    }

    /** Why chunk $index can't be used, or null when it matches the layout. */
    public static function chunkProblem(?array $chunk, int $index): ?string
    {
        if ($chunk === null) {
            return 'missing';
        }
        if (($chunk['index'] ?? null) !== $index) {
            return 'index does not match';
        }
        if (($chunk['firstFrame'] ?? null) !== $index * self::FRAMES_PER_CHUNK) {
            return 'firstFrame does not match';
        }
        $frames = $chunk['frames'] ?? null;
        if (! is_int($frames) || $frames < 1 || $frames > self::FRAMES_PER_CHUNK) {
            return 'bad frame count';
        }
        $data = $chunk['data'] ?? null;
        if (! $data instanceof FirestoreBytes) {
            return 'data is not bytes';
        }
        if ($data->length() !== $frames * self::FRAME_BYTES) {
            return "data is {$data->length()} bytes, expected ".($frames * self::FRAME_BYTES);
        }

        return null;
    }

    public static function chunkId(int $index): string
    {
        return sprintf('c%03d', $index);
    }

    private function unavailable(string $sessionPath, string $reason, array $context = []): void
    {
        Log::warning('replay.unavailable', ['session' => $sessionPath, 'reason' => $reason] + $context);
    }
}
