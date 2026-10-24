<?php

namespace App\Services\Patient;

use App\Services\Firebase\FirebaseException;
use App\Services\Firebase\FirestoreClient;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\Log;

/**
 * Which Terms of Service / Privacy Policy version a patient accepted in the
 * app (patients/{uid}/consents/{version}, see API_CONTRACT.md "Consents").
 *
 * The app writes one document per version the patient accepted and never
 * deletes them. The dashboard only reads them: a patient who withdraws
 * consent is archived, and their consent records are kept as evidence.
 */
class ConsentService
{
    /** Patient accepted the version the app currently ships. */
    public const CURRENT = 'current';

    /** Patient accepted an older version; the app asks them again on next open. */
    public const OUTDATED = 'outdated';

    /** No consent record yet: the patient hasn't signed in to the app. */
    public const NONE = 'none';

    /** The consent records couldn't be read (Firebase error or bad uid). */
    public const UNAVAILABLE = 'unavailable';

    /** Version strings longer than this are treated as corrupt. */
    private const MAX_VERSION_LENGTH = 40;

    public function __construct(private FirestoreClient $db)
    {
    }

    /**
     * The patient's consent status, ready for the profile page.
     *
     * Never throws for a Firebase failure: consent status is a small part of
     * the profile, so a failed read is logged and reported as "unavailable"
     * instead of taking the whole page down. Safe to run inside
     * FirestoreClient::concurrently(), where a thrown error would otherwise
     * fail every other read in the batch too.
     *
     * @return array{status: string, version: ?string, acceptedAt: ?CarbonImmutable, currentVersion: string, flags: array<string, bool>}
     */
    public function forPatient(string $patientUid): array
    {
        if (! FirestoreClient::isValidId($patientUid)) {
            // Callers have already validated the uid; reaching here is a bug.
            Log::warning('consents.invalid_patient_id', ['patient' => mb_substr($patientUid, 0, 130)]);

            return self::status(self::UNAVAILABLE);
        }

        try {
            $docs = $this->db->query("patients/{$patientUid}", 'consents');
        } catch (FirebaseException $e) {
            Log::warning('consents.unreadable', ['patient' => $patientUid, 'error' => $e->getMessage()]);

            return self::status(self::UNAVAILABLE);
        }

        return self::summarise($docs);
    }

    /**
     * The consent version the app currently asks patients to accept.
     * Comes from config/services.php (legal.consent_version).
     */
    public static function currentVersion(): string
    {
        $version = config('services.legal.consent_version');

        return is_string($version) && $version !== '' ? $version : 'unknown';
    }

    /**
     * Status from the raw consent documents (as decoded by FirestoreClient).
     *
     * Consent documents are written by the patient's own phone, so every
     * field is treated as untrusted and coerced to the type the view
     * expects: a map where text is expected would otherwise crash the
     * profile page for every staff member.
     */
    public static function summarise(array $docs): array
    {
        $consents = array_map(fn (array $doc) => self::presentConsent($doc), $docs);
        $consents = array_values(array_filter($consents, fn (array $c) => $c['version'] !== null));

        if ($consents === []) {
            return self::status(self::NONE);
        }

        usort($consents, fn (array $a, array $b) => self::compareNewestFirst($a, $b));
        $newest = $consents[0];

        // Versions are ISO dates (e.g. "2026-10-18"), so string order is date
        // order. A version newer than ours means the app shipped new terms
        // before the dashboard config was bumped; that's still "accepted".
        $isCurrent = strcmp($newest['version'], self::currentVersion()) >= 0;

        return self::status(
            $isCurrent ? self::CURRENT : self::OUTDATED,
            $newest['version'],
            $newest['acceptedAt'],
            $newest['flags'],
        );
    }

    /**
     * One consent document, with every field coerced to a safe type.
     *
     * The version falls back to the document id, which the contract says is
     * the version string too.
     */
    private static function presentConsent(array $doc): array
    {
        $version = self::version($doc['version'] ?? null) ?? self::version($doc['_id'] ?? null);
        $acceptedAt = $doc['acceptedAt'] ?? null;

        return [
            'version' => $version,
            'acceptedAt' => $acceptedAt instanceof CarbonImmutable ? $acceptedAt : null,
            'flags' => [
                'Terms' => ($doc['acceptedTerms'] ?? false) === true,
                'Privacy' => ($doc['acceptedPrivacyPolicy'] ?? false) === true,
                'Health data' => ($doc['healthDataConsent'] ?? false) === true,
                'Camera' => ($doc['cameraConsent'] ?? false) === true,
            ],
        ];
    }

    /**
     * Sort order for consents: latest acceptedAt first. When either record
     * has no usable acceptedAt (or both have the same one), fall back to the
     * version string, which is an ISO date.
     */
    private static function compareNewestFirst(array $a, array $b): int
    {
        if ($a['acceptedAt'] !== null && $b['acceptedAt'] !== null) {
            $byTime = $b['acceptedAt']->getTimestamp() <=> $a['acceptedAt']->getTimestamp();
            if ($byTime !== 0) {
                return $byTime;
            }
        }

        return strcmp($b['version'], $a['version']);
    }

    /** A non-empty, reasonably short version string; anything else is null. */
    private static function version(mixed $value): ?string
    {
        if (! is_string($value)) {
            return null;
        }

        $value = trim($value);

        return $value !== '' && mb_strlen($value) <= self::MAX_VERSION_LENGTH ? $value : null;
    }

    private static function status(string $status, ?string $version = null, ?CarbonImmutable $acceptedAt = null, array $flags = []): array
    {
        return [
            'status' => $status,
            'version' => $version,
            'acceptedAt' => $acceptedAt,
            'currentVersion' => self::currentVersion(),
            'flags' => $flags,
        ];
    }
}
