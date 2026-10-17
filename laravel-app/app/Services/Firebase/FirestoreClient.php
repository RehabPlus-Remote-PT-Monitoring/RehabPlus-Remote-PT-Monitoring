<?php

namespace App\Services\Firebase;

use Carbon\CarbonImmutable;
use DateTimeInterface;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\Client\PendingRequest;
use Illuminate\Http\Client\Response;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Str;

/**
 * Minimal Firestore REST client (no grpc extension needed).
 *
 * Paths are relative to the database root, e.g. "patients/abc/threads/clinic".
 * Documents come back as plain arrays: their fields (timestamps as
 * CarbonImmutable) plus "_id" and "_path".
 *
 * The service account bypasses Firestore security rules, so callers must do
 * their own permission checks (see API_CONTRACT.md in the app repo).
 */
class FirestoreClient
{
    public function __construct(private GoogleAccessToken $token)
    {
    }

    public function projectId(): string
    {
        return config('services.firebase.project_id');
    }

    /** Full resource name of the database root ("projects/.../documents"). */
    public function root(): string
    {
        return "projects/{$this->projectId()}/databases/(default)/documents";
    }

    public function name(string $path): string
    {
        return $this->root().'/'.trim($path, '/');
    }

    public function get(string $path): ?array
    {
        $response = $this->send('get', $this->url($path));

        if ($response->status() === 404) {
            return null;
        }

        return $this->decodeDocument($this->ok($response)->json());
    }

    /**
     * Fetch several documents at once, keyed by path. Missing documents are null.
     *
     * @param  string[]  $paths
     * @return array<string, array|null>
     */
    public function getMany(array $paths): array
    {
        $result = array_fill_keys($paths, null);

        foreach (array_chunk($paths, 100) as $chunk) {
            $response = $this->ok($this->send('post', $this->url('').':batchGet', [
                'documents' => array_map(fn ($p) => $this->name($p), $chunk),
            ]));

            foreach ($response->json() as $entry) {
                if (isset($entry['found'])) {
                    $doc = $this->decodeDocument($entry['found']);
                    $result[$doc['_path']] = $doc;
                }
            }
        }

        return $result;
    }

    /**
     * Run a structured query against $collection under $parentPath
     * ("" for a top-level collection).
     *
     * @param  array  $where  [[field, op, value], ...] with op one of Firestore's
     *                        FieldFilter operators (EQUAL, GREATER_THAN, ...)
     * @param  array|null  $orderBy  [field, 'ASCENDING'|'DESCENDING']
     * @param  bool  $allDescendants  collection-group query: every $collection
     *                                below $parentPath (e.g. all patients' sessions).
     *                                Filters/ordering need a collection-group index,
     *                                so callers filter these in PHP instead.
     */
    public function query(string $parentPath, string $collection, array $where = [], ?array $orderBy = null, ?int $limit = null, bool $allDescendants = false): array
    {
        $query = ['from' => [array_filter(['collectionId' => $collection, 'allDescendants' => $allDescendants])]];

        $filters = array_map(fn ($w) => ['fieldFilter' => [
            'field' => ['fieldPath' => $w[0]],
            'op' => $w[1],
            'value' => $this->encode($w[2]),
        ]], $where);

        if (count($filters) === 1) {
            $query['where'] = $filters[0];
        } elseif ($filters) {
            $query['where'] = ['compositeFilter' => ['op' => 'AND', 'filters' => $filters]];
        }
        if ($orderBy) {
            $query['orderBy'] = [['field' => ['fieldPath' => $orderBy[0]], 'direction' => $orderBy[1]]];
        }
        if ($limit) {
            $query['limit'] = $limit;
        }

        $response = $this->ok($this->send('post', $this->url($parentPath).':runQuery', [
            'structuredQuery' => $query,
        ]));

        return collect($response->json())
            ->filter(fn ($row) => isset($row['document']))
            ->map(fn ($row) => $this->decodeDocument($row['document']))
            ->values()
            ->all();
    }

    /** Apply writes atomically. Build them with the write helpers below. */
    public function commit(array $writes): void
    {
        $this->ok($this->send('post', $this->url('').':commit', ['writes' => $writes]));
    }

    public function delete(string $path): void
    {
        $this->ok($this->send('delete', $this->url($path)));
    }

    /** A new random document id, same format as the Firebase SDKs. */
    public static function newId(): string
    {
        return Str::random(20);
    }

    /**
     * Whether $id is safe to put in a document path (Firebase uids and
     * generated ids are alphanumeric). Check every id that comes from a URL.
     */
    public static function isValidId(string $id): bool
    {
        return (bool) preg_match('/^[A-Za-z0-9_-]{1,128}$/', $id);
    }

    // ---- write builders ---------------------------------------------------

    /** Create a document; fails the whole commit if it already exists. */
    public function createWrite(string $path, array $fields, array $serverTimestamps = []): array
    {
        return array_filter([
            'update' => ['name' => $this->name($path), 'fields' => $this->encodeFields($fields)],
            'currentDocument' => ['exists' => false],
            'updateTransforms' => $this->timestampTransforms($serverTimestamps),
        ]);
    }

    /**
     * Set only the given fields (merge), creating the document if needed.
     *
     * @param  array<string, int>  $increments  field => amount
     */
    public function mergeWrite(string $path, array $fields, array $increments = [], array $serverTimestamps = []): array
    {
        $transforms = $this->timestampTransforms($serverTimestamps);
        foreach ($increments as $field => $by) {
            $transforms[] = ['fieldPath' => $field, 'increment' => $this->encode($by)];
        }

        return array_filter([
            'update' => ['name' => $this->name($path), 'fields' => $this->encodeFields($fields)],
            'updateMask' => ['fieldPaths' => array_keys($fields)],
            'updateTransforms' => $transforms,
        ]);
    }

    // ---- value encoding ---------------------------------------------------

    public function encodeFields(array $fields): array
    {
        return array_map(fn ($v) => $this->encode($v), $fields);
    }

    public function encode(mixed $value): array
    {
        return match (true) {
            $value === null => ['nullValue' => null],
            is_bool($value) => ['booleanValue' => $value],
            is_int($value) => ['integerValue' => (string) $value],
            is_float($value) => ['doubleValue' => $value],
            is_string($value) => ['stringValue' => $value],
            $value instanceof DateTimeInterface => [
                'timestampValue' => CarbonImmutable::instance($value)->utc()->format('Y-m-d\TH:i:s.u\Z'),
            ],
            is_array($value) && array_is_list($value) => [
                'arrayValue' => ['values' => array_map(fn ($v) => $this->encode($v), $value)],
            ],
            is_array($value) => ['mapValue' => ['fields' => $this->encodeFields($value)]],
            default => throw new FirebaseException('Unsupported Firestore value type: '.get_debug_type($value)),
        };
    }

    public function decode(array $value): mixed
    {
        $type = array_key_first($value);
        $v = $value[$type];

        return match ($type) {
            'nullValue' => null,
            'booleanValue' => (bool) $v,
            'integerValue' => (int) $v,
            'doubleValue' => (float) $v,
            'stringValue', 'referenceValue', 'bytesValue' => $v,
            'timestampValue' => CarbonImmutable::parse($v),
            'arrayValue' => array_map(fn ($x) => $this->decode($x), $v['values'] ?? []),
            'mapValue' => array_map(fn ($x) => $this->decode($x), $v['fields'] ?? []),
            default => $v,
        };
    }

    // ---- internals --------------------------------------------------------

    private function decodeDocument(array $doc): array
    {
        $path = Str::after($doc['name'], $this->root().'/');

        return array_map(fn ($v) => $this->decode($v), $doc['fields'] ?? []) + [
            '_id' => Str::afterLast($path, '/'),
            '_path' => $path,
        ];
    }

    private function timestampTransforms(array $fields): array
    {
        return array_map(fn ($f) => ['fieldPath' => $f, 'setToServerValue' => 'REQUEST_TIME'], $fields);
    }

    private function url(string $path): string
    {
        return 'https://firestore.googleapis.com/v1/'.rtrim($this->name($path), '/');
    }

    private function http(): PendingRequest
    {
        return Http::withToken($this->token->get())->acceptJson()->timeout(15);
    }

    /** Network failures become FirebaseException so pages can show a friendly error. */
    private function send(string $method, string $url, array $data = []): Response
    {
        try {
            return $this->http()->{$method}($url, $data);
        } catch (ConnectionException $e) {
            throw new FirebaseException('Could not reach Firebase (network error).', 0, $e);
        }
    }

    private function ok(Response $response): Response
    {
        if ($response->failed()) {
            $message = $response->json('error.message') ?? $response->json('0.error.message') ?? $response->body();
            throw new FirebaseException('Firestore request failed ('.$response->status().'): '.Str::limit((string) $message, 300));
        }

        return $response;
    }
}
