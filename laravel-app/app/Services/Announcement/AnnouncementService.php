<?php

namespace App\Services\Announcement;

use App\Auth\StaffUser;
use App\Services\Firebase\FirestoreClient;
use App\Services\User\StaffDirectory;
use Illuminate\Http\UploadedFile;
use Illuminate\Validation\ValidationException;

/**
 * Clinic announcements (Firestore `announcements`), shown on the dashboard and
 * the welcome page. An announcement can have a picture and an optional last
 * day it is shown.
 */
class AnnouncementService
{
    private const COLLECTION = 'announcements';

    private const LIST_LIMIT = 20;

    /** Longest side of a stored picture, in pixels. */
    private const MAX_SIDE = 1200;

    /** Firestore documents are capped at 1 MiB; base64 adds a third, so the picture stays under this. */
    private const MAX_IMAGE_CHARS = 900000;

    public function __construct(private FirestoreClient $db)
    {
    }

    /** The announcements to show today, newest first. */
    public function current(): array
    {
        $today = now()->toDateString();
        $docs = $this->db->query('', self::COLLECTION, orderBy: ['postedAt', 'DESCENDING'], limit: self::LIST_LIMIT);

        $shown = array_filter($docs, fn (array $doc) => empty($doc['showUntil']) || $doc['showUntil'] >= $today);

        return array_values(array_map(fn (array $doc) => $this->present($doc), $shown));
    }

    public function create(array $data, StaffUser $by): string
    {
        $id = FirestoreClient::newId();

        $this->db->commit([$this->db->createWrite(self::COLLECTION."/{$id}", [
            'title' => $data['title'],
            'body' => $data['body'],
            'imageUrl' => $data['imageUrl'] ?? null,
            'showUntil' => $data['show_until'] ?? null,
            'postedById' => $by->id,
            'postedByName' => $by->name,
        ], serverTimestamps: ['postedAt'])]);

        return $id;
    }

    public function delete(string $id): void
    {
        $this->db->delete(self::COLLECTION."/{$id}");
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
        ];
    }
}
