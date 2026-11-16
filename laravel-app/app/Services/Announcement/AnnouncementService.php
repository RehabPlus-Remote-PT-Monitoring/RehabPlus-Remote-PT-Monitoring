<?php

namespace App\Services\Announcement;

use App\Auth\StaffUser;
use App\Services\Firebase\FirebaseException;
use App\Services\Firebase\FirestoreClient;
use App\Services\User\StaffDirectory;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Cache;
use Illuminate\Validation\ValidationException;

/**
 * Clinic announcements (Firestore `announcements`), shown on the dashboard and
 * the welcome page. An announcement can have a picture and an optional last
 * day it is shown.
 */
class AnnouncementService
{
    private const COLLECTION = 'announcements';

    /**
     * The newest announcements are cached briefly, so each visit to the welcome page doesn't wait on
     * Firestore. Posting, archiving and deleting clear it at once; "show until" is still checked on every load.
     */
    private const RECENT_CACHE_KEY = 'announcements-recent';

    private const RECENT_CACHE_SECONDS = 300;

    /** The last announcements read successfully. Shown if Firestore is slow or down, so the welcome page doesn't wait on it. */
    private const LAST_GOOD_KEY = 'announcements-last-good';

    private const LIST_LIMIT = 20;

    private const MANAGE_LIMIT = 100;

    /** Longest side of a stored picture, in pixels. */
    private const MAX_SIDE = 1200;

    /** Firestore documents are capped at 1 MiB; base64 adds a third, so the picture stays under this. */
    private const MAX_IMAGE_CHARS = 900000;

    public function __construct(private FirestoreClient $db)
    {
    }

    /** The announcements visitors see today, newest first. Archived ones are left out. */
    public function current(): array
    {
        $today = now()->toDateString();
        $docs = $this->recentDocs();

        $shown = array_filter($docs, fn (array $doc) => ! ($doc['archived'] ?? false)
            && (empty($doc['showUntil']) || $doc['showUntil'] >= $today));

        return array_values(array_map(fn (array $doc) => $this->present($doc), $shown));
    }

    /**
     * Every announcement for the management page: the current ones first, then the
     * archived ones, each group newest first.
     */
    public function manage(): array
    {
        $docs = array_map(fn (array $doc) => $this->present($doc), $this->db->query('', self::COLLECTION, orderBy: ['postedAt', 'DESCENDING'], limit: self::MANAGE_LIMIT));

        usort($docs, fn (array $a, array $b) => [$a['archived'] ? 1 : 0] <=> [$b['archived'] ? 1 : 0]);

        return $docs;
    }

    /**
     * The newest raw announcement documents, cached for five minutes (see RECENT_CACHE_KEY). If Firestore
     * fails, the last announcements read successfully are used instead of an error.
     */
    private function recentDocs(): array
    {
        try {
            $docs = Cache::remember(self::RECENT_CACHE_KEY, self::RECENT_CACHE_SECONDS, fn () => $this->db->query(
                '',
                self::COLLECTION,
                orderBy: ['postedAt', 'DESCENDING'],
                limit: self::LIST_LIMIT,
            ));
        } catch (FirebaseException) {
            return Cache::get(self::LAST_GOOD_KEY, []);
        }

        Cache::forever(self::LAST_GOOD_KEY, $docs);

        return $docs;
    }

    /** Writes clear both copies, so a deleted or archived announcement can't come back during an outage. */
    private function forgetRecent(): void
    {
        Cache::forget(self::RECENT_CACHE_KEY);
        Cache::forget(self::LAST_GOOD_KEY);
    }

    public function setArchived(string $id, bool $archived): void
    {
        $change = $archived
            ? ['archived' => true]
            : ['archived' => false, 'archivedAt' => null];

        $this->db->commit([$this->db->mergeWrite(self::COLLECTION."/{$id}", $change, serverTimestamps: $archived ? ['archivedAt'] : [])]);
        $this->forgetRecent();
    }

    public function create(array $data, StaffUser $by): string
    {
        $id = FirestoreClient::newId();

        $this->db->commit([$this->db->createWrite(self::COLLECTION."/{$id}", [
            'title' => $data['title'],
            'body' => (string) ($data['body'] ?? ''),
            'imageUrl' => $data['imageUrl'] ?? null,
            'showUntil' => $data['show_until'] ?? null,
            // A story is a picture shown in the "Today at Rehab+" row on the welcome page.
            'story' => (bool) ($data['story'] ?? false),
            'postedById' => $by->id,
            'postedByName' => $by->name,
        ], serverTimestamps: ['postedAt'])]);
        $this->forgetRecent();

        return $id;
    }

    public function delete(string $id): void
    {
        $this->db->delete(self::COLLECTION."/{$id}");
        $this->forgetRecent();
    }

    /**
     * The picture as a data URL. Large photos are resized to a JPEG when the
     * server has GD, so they fit in one Firestore document.
     */
    public function imageDataUrl(UploadedFile $file): string
    {
        $bytes = $file->get();
        $mime = $file->getMimeType();

        if (function_exists('imagecreatefromstring') && ($image = @imagecreatefromstring($bytes)) !== false) {
            $width = imagesx($image);
            $height = imagesy($image);
            $scale = min(1, self::MAX_SIDE / max($width, $height));
            $canvas = imagecreatetruecolor((int) round($width * $scale), (int) round($height * $scale));

            // A white background, so transparent PNGs don't turn black as JPEG.
            imagefill($canvas, 0, 0, imagecolorallocate($canvas, 255, 255, 255));
            imagecopyresampled($canvas, $image, 0, 0, 0, 0, imagesx($canvas), imagesy($canvas), $width, $height);

            ob_start();
            imagejpeg($canvas, null, 82);
            $bytes = ob_get_clean();
            $mime = 'image/jpeg';
        }

        $dataUrl = 'data:'.$mime.';base64,'.base64_encode($bytes);

        if (strlen($dataUrl) > self::MAX_IMAGE_CHARS) {
            throw ValidationException::withMessages(['image' => 'That picture is too large. Choose a smaller one.']);
        }

        return $dataUrl;
    }

    private function present(array $doc): array
    {
        return [
            'id' => $doc['_id'],
            'title' => (string) ($doc['title'] ?? ''),
            'body' => (string) ($doc['body'] ?? ''),
            'imageUrl' => StaffDirectory::safePhotoUrl($doc['imageUrl'] ?? null),
            'postedAt' => $doc['postedAt'] ?? null,
            'postedByName' => (string) ($doc['postedByName'] ?? ''),
            'showUntil' => $doc['showUntil'] ?? null,
            'archived' => (bool) ($doc['archived'] ?? false),
            'story' => (bool) ($doc['story'] ?? false),
        ];
    }

    /**
     * The posts marked as stories that are still shown: picture posts, not archived, and not past their
     * "show until" date. Shown in the "Today at Rehab+" row on the welcome page.
     */
    public function stories(): array
    {
        $today = now()->toDateString();
        $shown = array_filter($this->recentDocs(), fn (array $doc) => ($doc['story'] ?? false) === true
            && ! ($doc['archived'] ?? false)
            && (empty($doc['showUntil']) || $doc['showUntil'] >= $today)
            && is_string($doc['imageUrl'] ?? null));

        $presented = array_map(fn (array $doc) => $this->present($doc), $shown);

        return array_values(array_filter($presented, fn (array $story) => $story['imageUrl'] !== ''));
    }
}
