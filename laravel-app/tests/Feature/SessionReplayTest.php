<?php

namespace Tests\Feature;

use App\Services\Firebase\FirebaseException;
use App\Services\Firebase\FirestoreBytes;
use App\Services\Firebase\FirestoreClient;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\Log;
use Illuminate\Testing\TestResponse;
use Mockery;
use Tests\Support\FakeFirebase;
use Tests\TestCase;

/**
 * Movement replay page (GET /patients/{uid}/sessions/{id}/replay): the
 * pose points the app saved under patients/{uid}/sessions/{id}/replay,
 * byte layout in API_CONTRACT.md. The fake Firestore serves the chunk
 * bytes as base64 `bytesValue`, exactly like the REST API.
 */
class SessionReplayTest extends TestCase
{
    use FakeFirebase;

    private const SESSION = 'patients/pOne/sessions/s1';

    protected function setUp(): void
    {
        parent::setUp();

        $this->patientDoc('pOne', ['name' => 'Olive One', 'therapistId' => 'thA', 'therapistName' => 'Dr. Ana']);
        $this->patientDoc('pTwo', ['name' => 'Tom Two', 'therapistId' => 'thB', 'therapistName' => 'Dr. Ben']);
        $this->docs[self::SESSION] = [
            'exerciseId' => 'wallSquat', 'exerciseName' => 'Wall squats',
            'startTime' => CarbonImmutable::parse('2026-11-14 01:30:00', 'UTC'),
            'completedReps' => 8, 'targetReps' => 10, 'rejectedReps' => 2,
            'overallCompliance' => 0.85, 'painLevel' => 3, 'endedEarly' => true,
            'hasReplay' => true,
        ];
    }

    private function therapist()
    {
        return $this->staff('therapist', 'thA', 'Dr. Ana');
    }

    /** One 171-byte frame record: uint32 t, uint16 angle x 10, 33 x (uint16 x, uint16 y, uint8 conf). */
    private static function frame(int $t, ?float $angle = 92.5, bool $empty = false): string
    {
        $bytes = pack('V', $t).pack('v', $angle === null ? 0xFFFF : (int) round($angle * 10));
        for ($i = 0; $i < 33; $i++) {
            $bytes .= $empty || $i === 0
                ? pack('vvC', 0xFFFF, 0xFFFF, 0)          // missing landmark (always the nose here)
                : pack('vvC', 1000 + $i * 200, 2000 + $i * 150, 230);
        }

        return $bytes;
    }

    private static function chunkBytes(int $firstFrame, int $frames): string
    {
        $raw = '';
        for ($f = 0; $f < $frames; $f++) {
            $raw .= self::frame(($firstFrame + $f) * 100);
        }

        return $raw;
    }

    /** meta + chunks the way the app writes them; returns the raw chunk bytes. */
    private function seedReplay(array $metaOverrides = [], array $framesPerChunk = [300, 5]): array
    {
        $this->docs[self::SESSION.'/replay/meta'] = $metaOverrides + [
            'version' => 1, 'fps' => 10, 'frameCount' => array_sum($framesPerChunk),
            'chunkCount' => count($framesPerChunk), 'durationMs' => (array_sum($framesPerChunk) - 1) * 100,
            'truncated' => false, 'aspect' => 0.5625, 'mirrored' => true, 'angleLabel' => 'Knee angle',
            'events' => [
                ['t' => 1500, 'kind' => 'counted', 'note' => ''],
                ['t' => 3200, 'kind' => 'rejected', 'note' => 'Knees went past your toes'],
                ['t' => 5000, 'kind' => 'hold', 'note' => 'Held 5 s'],
            ],
            'createdAt' => CarbonImmutable::now(),
        ];

        $raws = [];
        foreach ($framesPerChunk as $i => $frames) {
            $raws[$i] = self::chunkBytes($i * 300, $frames);
            $this->docs[self::SESSION.'/replay/'.sprintf('c%03d', $i)] = [
                'index' => $i, 'firstFrame' => $i * 300, 'frames' => $frames, 'data' => new FirestoreBytes($raws[$i]),
            ];
        }

        return $raws;
    }

    /** The JSON the page hands to the player. */
    private function payload(TestResponse $response): array
    {
        $this->assertMatchesRegularExpression('#<script type="application/json" data-replay-data nonce="[^"]+">#', $response->getContent());
        preg_match('#<script type="application/json" data-replay-data[^>]*>(.*?)</script>#s', $response->getContent(), $m);

        return json_decode($m[1], true, flags: JSON_THROW_ON_ERROR);
    }

    public function test_therapist_sees_the_replay_of_their_own_patient(): void
    {
        $raws = $this->seedReplay();

        $response = $this->actingAs($this->therapist())->get('/patients/pOne/sessions/s1/replay')->assertOk();

        $data = $this->payload($response);
        $this->assertCount(2, $data['chunks']);
        $this->assertSame($raws[0], base64_decode($data['chunks'][0], true));   // bytes round-trip untouched
        $this->assertSame($raws[1], base64_decode($data['chunks'][1], true));
        $this->assertTrue($data['mirrored']);
        $this->assertSame(0.5625, $data['aspect']);
        $this->assertSame('Knee angle', $data['angleLabel']);
        $this->assertSame(['counted', 'rejected', 'hold'], array_column($data['events'], 'kind'));

        $response->assertSee('Movement replay')
            ->assertSee('Wall squats')
            ->assertSee('8 of 10')
            ->assertSee('85%')
            ->assertSee('3/10')
            ->assertSeeInOrder(['Ended early', 'Yes'])
            ->assertSee('This is the body-tracking data the app used, not a video.')
            ->assertSee('data-replay-seek="3200"', false)
            ->assertSee('Knees went past your toes')
            ->assertSee(route('patients.show', 'pOne'), false)
            ->assertSee('session-replay', false)          // the player module is loaded
            ->assertDontSee('No replay available');
        $this->assertSame([], $this->commits);              // read-only
    }

    public function test_admin_can_open_any_patients_replay(): void
    {
        $this->seedReplay();

        $this->actingAs($this->staff('admin'))->get('/patients/pOne/sessions/s1/replay')
            ->assertOk()->assertSee('data-replay-data', false);
    }

    public function test_other_therapist_gets_404(): void
    {
        $this->seedReplay();

        $this->actingAs($this->staff('therapist', 'thB', 'Dr. Ben'))->get('/patients/pOne/sessions/s1/replay')
            ->assertNotFound();
    }

    public function test_front_desk_staff_are_forbidden(): void
    {
        $this->seedReplay();

        $this->actingAs($this->staff('staff', 'deskUid', 'Desk Person'))->get('/patients/pOne/sessions/s1/replay')
            ->assertForbidden();
    }

    public function test_guests_are_sent_to_login(): void
    {
        $this->get('/patients/pOne/sessions/s1/replay')->assertRedirect();
    }

    public function test_unknown_or_malformed_ids_are_404(): void
    {
        $this->seedReplay();
        $therapist = $this->therapist();

        $this->actingAs($therapist)->get('/patients/pOne/sessions/nope/replay')->assertNotFound();
        $this->actingAs($therapist)->get('/patients/pOne/sessions/bad.id/replay')->assertNotFound();
        $this->actingAs($therapist)->get('/patients/pOne/sessions/'.str_repeat('a', 129).'/replay')->assertNotFound();
        $this->actingAs($therapist)->get('/patients/nobody/sessions/s1/replay')->assertNotFound();
    }

    public function test_missing_replay_shows_a_friendly_message(): void
    {
        Log::spy();

        $this->actingAs($this->therapist())->get('/patients/pOne/sessions/s1/replay')
            ->assertOk()
            ->assertSee('No replay available for this session')
            ->assertSee('8 of 10')                          // the summary still shows
            ->assertDontSee('data-replay-data', false)
            ->assertDontSee('session-replay', false);

        // hasReplay said there would be one, so it's worth a warning.
        Log::shouldHaveReceived('warning')->with('replay.unavailable', Mockery::on(
            fn ($c) => $c['reason'] === 'no meta document' && $c['session'] === self::SESSION,
        ));
    }

    public function test_failed_replay_read_still_shows_the_session(): void
    {
        Log::spy();
        $this->seedReplay();
        $this->actingAs($this->therapist())->get('/profile');      // loads the staff directory first
        $this->injectedFailures[':batchGet'] = [403];

        $this->actingAs($this->therapist())->get('/patients/pOne/sessions/s1/replay')
            ->assertOk()
            ->assertSee('No replay available for this session')
            ->assertSee('Wall squats');

        Log::shouldHaveReceived('warning')->with('replay.unavailable', Mockery::on(fn ($c) => $c['reason'] === 'read failed'));
    }

    public function test_corrupt_chunk_is_skipped_and_logged(): void
    {
        Log::spy();
        $raws = $this->seedReplay();
        // One byte short of 5 frames.
        $this->docs[self::SESSION.'/replay/c001']['data'] = new FirestoreBytes(substr($raws[1], 0, -1));

        $response = $this->actingAs($this->therapist())->get('/patients/pOne/sessions/s1/replay')->assertOk();

        $data = $this->payload($response);
        $this->assertCount(1, $data['chunks']);
        $this->assertSame($raws[0], base64_decode($data['chunks'][0], true));
        $response->assertSee('Part of this replay could not be loaded');

        Log::shouldHaveReceived('warning')->with('replay.chunk_skipped', Mockery::on(
            fn ($c) => $c['chunk'] === 'c001' && $c['reason'] === 'data is 854 bytes, expected 855',
        ));
    }

    public function test_bad_first_chunk_means_no_replay(): void
    {
        Log::spy();
        $this->seedReplay();
        $this->docs[self::SESSION.'/replay/c000']['index'] = 7;

        $this->actingAs($this->therapist())->get('/patients/pOne/sessions/s1/replay')
            ->assertOk()->assertSee('No replay available for this session');

        Log::shouldHaveReceived('warning')->with('replay.chunk_skipped', Mockery::on(fn ($c) => $c['reason'] === 'index does not match'));
        Log::shouldHaveReceived('warning')->with('replay.unavailable', Mockery::on(fn ($c) => $c['reason'] === 'no readable chunks'));
    }

    public function test_data_that_is_not_bytes_or_has_wrong_frames_is_rejected(): void
    {
        $this->seedReplay([], [3]);
        $this->docs[self::SESSION.'/replay/c000']['data'] = base64_encode(self::chunkBytes(0, 3));   // a string, not bytes

        $this->actingAs($this->therapist())->get('/patients/pOne/sessions/s1/replay')
            ->assertOk()->assertSee('No replay available for this session');

        $this->seedReplay([], [3]);
        $this->docs[self::SESSION.'/replay/c000']['frames'] = 301;

        $this->actingAs($this->therapist())->get('/patients/pOne/sessions/s1/replay')
            ->assertOk()->assertSee('No replay available for this session');
    }

    public function test_unsupported_version_or_chunk_count_means_no_replay(): void
    {
        $this->seedReplay(['version' => 2]);
        $this->actingAs($this->therapist())->get('/patients/pOne/sessions/s1/replay')
            ->assertOk()->assertSee('No replay available for this session');

        $this->seedReplay(['chunkCount' => 21]);
        $this->actingAs($this->therapist())->get('/patients/pOne/sessions/s1/replay')
            ->assertOk()->assertSee('No replay available for this session');
    }

    public function test_meta_and_events_are_coerced(): void
    {
        $valid = array_map(fn ($i) => ['t' => 10000 + $i, 'kind' => 'counted', 'note' => ''], range(1, 205));
        $this->seedReplay([
            'fps' => 50,
            'aspect' => 99.0,
            'mirrored' => 'yes',
            'angleLabel' => str_repeat('L', 80),
            'events' => [
                ['t' => 900, 'kind' => 'rejected', 'note' => str_repeat('n', 150)],
                ['t' => -5, 'kind' => 'counted', 'note' => ''],
                ['t' => '20', 'kind' => 'counted', 'note' => ''],
                ['t' => 30, 'kind' => 'evil', 'note' => ''],
                ['t' => 40, 'kind' => 'hold', 'note' => ['not' => 'text']],
                ['t' => 1.5, 'kind' => 'hold', 'note' => ''],
                'just a string',
                [1, 2, 3],
                ['t' => 100, 'kind' => 'counted', 'note' => '</script><script>alert(1)</script>'],
                ...$valid,
            ],
        ]);

        $response = $this->actingAs($this->therapist())->get('/patients/pOne/sessions/s1/replay')->assertOk();
        $data = $this->payload($response);

        $this->assertSame(10, $data['fps']);
        $this->assertSame(5, $data['aspect']);            // JSON drops the .0
        $this->assertFalse($data['mirrored']);            // only a real true
        $this->assertSame(str_repeat('L', 60), $data['angleLabel']);

        $events = $data['events'];
        $this->assertCount(200, $events);                 // capped
        $this->assertSame([40, 100, 900], array_column(array_slice($events, 0, 3), 't'));   // sorted, bad ones dropped
        $this->assertSame('', $events[0]['note']);        // a map note becomes empty
        $this->assertSame(120, mb_strlen($events[2]['note']));

        // The note can't break out of the data block.
        $this->assertStringNotContainsString('</script><script>alert(1)', $response->getContent());
        $this->assertSame('</script><script>alert(1)</script>', $events[1]['note']);
    }

    public function test_replay_link_only_for_sessions_with_has_replay_true(): void
    {
        $this->docs['patients/pOne/sessions/s2'] = ['exerciseName' => 'Lunges', 'startTime' => CarbonImmutable::now()->subDay(), 'hasReplay' => 'true'];
        $this->docs['patients/pOne/sessions/s3'] = ['exerciseName' => 'Bridges', 'startTime' => CarbonImmutable::now()->subDays(2)];
        $this->docs['patients/pOne/sessions/s4'] = ['exerciseName' => 'Heel raises', 'startTime' => CarbonImmutable::now()->subDays(3), 'hasReplay' => 1];

        $html = $this->actingAs($this->therapist())->get('/patients/pOne')->assertOk()->getContent();

        $this->assertStringContainsString('href="'.route('sessions.replay', ['pOne', 's1']).'"', $html);
        $this->assertSame(1, substr_count($html, 'data-replay-link'));
        foreach (['s2', 's3', 's4'] as $id) {
            $this->assertStringNotContainsString(route('sessions.replay', ['pOne', $id]), $html);
        }
    }

    public function test_bytes_values_round_trip_like_the_rest_api(): void
    {
        $db = app(FirestoreClient::class);
        $raw = "\x00\xFF\xFF\x10binary";

        $encoded = $db->encode(new FirestoreBytes($raw));
        $this->assertSame(['bytesValue' => base64_encode($raw)], $encoded);

        $decoded = $db->decode($encoded);
        $this->assertInstanceOf(FirestoreBytes::class, $decoded);
        $this->assertSame($raw, $decoded->raw);
        $this->assertSame(strlen($raw), $decoded->length());

        $this->expectException(FirebaseException::class);
        $db->decode(['bytesValue' => 'not base64!!']);
    }
}
