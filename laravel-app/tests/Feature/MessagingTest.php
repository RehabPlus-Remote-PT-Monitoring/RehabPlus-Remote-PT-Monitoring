<?php

namespace Tests\Feature;

use App\Models\User;
use App\Services\Firebase\FirestoreClient;
use App\Services\Firebase\GoogleAccessToken;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * Staff messaging against a fake Firestore / Firebase Auth / FCM (Http::fake),
 * so no network or real Firebase project is touched.
 */
class MessagingTest extends TestCase
{
    use RefreshDatabase;

    private const ROOT = 'projects/rehabplus-80675/databases/(default)/documents';

    /** @var array<string, array> path => plain fields */
    private array $docs = [];

    /** @var array<string, string> email => Firebase uid */
    private array $authUsers = ['thera@rehabplus.com' => 'therapistUid1'];

    /** Write batches sent to :commit */
    private array $commits = [];

    private array $deleted = [];

    private array $pushes = [];

    protected function setUp(): void
    {
        parent::setUp();

        config(['services.firebase.credentials' => __FILE__, 'services.firebase.project_id' => 'rehabplus-80675']);
        $this->instance(GoogleAccessToken::class, new class extends GoogleAccessToken
        {
            public function get(): string
            {
                return 'test-token';
            }
        });

        $t = CarbonImmutable::parse('2026-10-18 09:00:00');
        $this->docs = [
            'patients/pAnna' => ['name' => 'Anna Cruz', 'condition' => 'ACL rehab', 'therapistId' => 'therapistUid1', 'therapistName' => 'Dr. Reyes'],
            'patients/pBen' => ['name' => 'Ben Lim', 'condition' => 'Shoulder', 'therapistId' => 'otherTherapist'],
            'patients/pAnna/threads/therapist' => ['lastMessage' => 'My knee hurts', 'lastMessageAt' => $t, 'lastSenderRole' => 'patient', 'unreadForStaff' => 2],
            'patients/pAnna/threads/therapist/messages/m1' => ['text' => 'Hi doc', 'senderRole' => 'patient', 'sentAt' => $t->subMinute()],
            'patients/pAnna/threads/therapist/messages/m2' => ['text' => 'My knee hurts', 'senderRole' => 'patient', 'sentAt' => $t],
            'patients/pBen/threads/clinic' => ['lastMessage' => 'Can I book Tuesday?', 'lastMessageAt' => $t, 'lastSenderRole' => 'patient', 'unreadForStaff' => 1],
            'patients/pAnna/devices/goodToken' => ['token' => 'goodToken'],
            'patients/pAnna/devices/deadToken' => ['token' => 'deadToken'],
        ];

        Http::fake(fn (Request $r) => $this->fakeGoogle($r));
    }

    public function test_therapist_inbox_lists_only_their_patients(): void
    {
        $this->actingAs($this->user('therapist', 'thera@rehabplus.com'))
            ->get('/messages')
            ->assertOk()
            ->assertSee('Anna Cruz')
            ->assertSee('My knee hurts')
            ->assertDontSee('Ben Lim');
    }

    public function test_clinic_staff_inbox_lists_clinic_threads(): void
    {
        $this->actingAs($this->user('staff'))
            ->get('/messages')
            ->assertOk()
            ->assertSee('Ben Lim')
            ->assertSee('Can I book Tuesday?')
            ->assertSee('Anna Cruz') // no clinic messages yet, still listed
            ->assertDontSee('My knee hurts'); // therapist thread is private
    }

    public function test_therapist_without_firebase_account_sees_warning(): void
    {
        $this->actingAs($this->user('therapist', 'nobody@rehabplus.com'))
            ->get('/messages')
            ->assertOk()
            ->assertSee('no matching Firebase account');
    }

    public function test_opening_a_conversation_shows_messages_and_marks_it_read(): void
    {
        $this->actingAs($this->user('therapist', 'thera@rehabplus.com'))
            ->get('/messages/pAnna')
            ->assertOk()
            ->assertSeeInOrder(['Hi doc', 'My knee hurts']);

        $write = $this->commits[0][0];
        $this->assertSame(self::ROOT.'/patients/pAnna/threads/therapist', $write['update']['name']);
        $this->assertSame(['unreadForStaff'], $write['updateMask']['fieldPaths']);
        $this->assertSame('0', $write['update']['fields']['unreadForStaff']['integerValue']);
    }

    public function test_therapist_cannot_open_another_therapists_patient(): void
    {
        $user = $this->user('therapist', 'thera@rehabplus.com');
        $this->actingAs($user)->get('/messages/pBen')->assertNotFound();
        $this->actingAs($user)->post('/messages/pBen', ['text' => 'hi'])->assertNotFound();
        $this->assertSame([], $this->commits);
    }

    public function test_patients_cannot_use_staff_messaging(): void
    {
        $this->actingAs($this->user('patient'))->get('/messages')->assertForbidden();
    }

    public function test_bad_patient_id_is_rejected_before_reaching_firestore(): void
    {
        $this->actingAs($this->user('staff'))->get('/messages/'.urlencode('pAnna/threads'))->assertNotFound();
    }

    public function test_reply_writes_message_thread_and_notification_then_pushes(): void
    {
        $this->actingAs($this->user('therapist', 'thera@rehabplus.com'))
            ->post('/messages/pAnna', ['text' => "  Ice it for 15 minutes.  "])
            ->assertRedirect('/messages/pAnna')
            ->assertSessionHas('success', 'Message sent.');

        [$message, $thread, $notification] = $this->commits[0];

        $this->assertStringStartsWith(self::ROOT.'/patients/pAnna/threads/therapist/messages/', $message['update']['name']);
        $this->assertSame(['exists' => false], $message['currentDocument']);
        $this->assertSame('Ice it for 15 minutes.', $message['update']['fields']['text']['stringValue']);
        $this->assertSame('staff', $message['update']['fields']['senderRole']['stringValue']);
        $this->assertSame('therapistUid1', $message['update']['fields']['senderId']['stringValue']);
        $this->assertArrayHasKey('timestampValue', $message['update']['fields']['sentAt']);
        $this->assertSame([['fieldPath' => 'createdAt', 'setToServerValue' => 'REQUEST_TIME']], $message['updateTransforms']);

        $this->assertSame(self::ROOT.'/patients/pAnna/threads/therapist', $thread['update']['name']);
        $this->assertSame(['lastMessage', 'lastMessageAt', 'lastSenderRole'], $thread['updateMask']['fieldPaths']);
        $this->assertSame([['fieldPath' => 'unreadForPatient', 'increment' => ['integerValue' => '1']]], $thread['updateTransforms']);

        $this->assertStringStartsWith(self::ROOT.'/patients/pAnna/notifications/', $notification['update']['name']);
        $this->assertSame('Message from Dr. Reyes', $notification['update']['fields']['title']['stringValue']);
        $this->assertSame('therapist', $notification['update']['fields']['data']['mapValue']['fields']['thread']['stringValue']);
        $this->assertFalse($notification['update']['fields']['read']['booleanValue']);

        // One push per device, with the app's chat channel; the dead token is removed.
        $this->assertCount(2, $this->pushes);
        $this->assertSame('chat_messages', $this->pushes[0]['android']['notification']['channel_id']);
        $this->assertSame(['type' => 'chat', 'thread' => 'therapist'], $this->pushes[0]['data']);
        $this->assertSame(['patients/pAnna/devices/deadToken'], $this->deleted);
    }

    public function test_clinic_reply_is_sent_as_the_clinic(): void
    {
        $this->actingAs($this->user('superadmin'))->post('/messages/pBen', ['text' => 'Tuesday 10am works.'])
            ->assertSessionHas('success', fn ($m) => str_contains($m, 'no phone is registered'));

        [$message, , $notification] = $this->commits[0];
        $this->assertStringContainsString('/patients/pBen/threads/clinic/messages/', $message['update']['name']);
        $this->assertSame('clinic', $message['update']['fields']['senderId']['stringValue']);
        $this->assertSame('Message from RehabPlus Clinic', $notification['update']['fields']['title']['stringValue']);
    }

    public function test_empty_and_too_long_replies_are_rejected(): void
    {
        $user = $this->user('therapist', 'thera@rehabplus.com');
        $this->actingAs($user)->post('/messages/pAnna', ['text' => ''])->assertSessionHasErrors('text');
        $this->actingAs($user)->post('/messages/pAnna', ['text' => str_repeat('a', 1001)])->assertSessionHasErrors('text');
        $this->assertSame([], $this->commits);
    }

    public function test_page_explains_missing_firebase_config(): void
    {
        config(['services.firebase.credentials' => null]);

        $this->actingAs($this->user('staff'))->get('/messages')->assertOk()->assertSee('FIREBASE_CREDENTIALS is missing');
    }

    public function test_firebase_outage_shows_friendly_errors(): void
    {
        Http::swap(new \Illuminate\Http\Client\Factory);
        Http::fake(fn () => Http::failedConnection());
        $user = $this->user('therapist', 'thera@rehabplus.com');

        $this->actingAs($user)->get('/messages')->assertOk()->assertSee('Could not load conversations');
        $this->actingAs($user)->get('/messages/pAnna')->assertStatus(503);
    }

    public function test_reply_still_succeeds_when_push_network_fails(): void
    {
        Http::swap(new \Illuminate\Http\Client\Factory);
        Http::fake(fn (Request $r) => str_contains($r->url(), 'fcm.googleapis.com')
            ? Http::failedConnection()
            : $this->fakeGoogle($r));

        $this->actingAs($this->user('therapist', 'thera@rehabplus.com'))
            ->post('/messages/pAnna', ['text' => 'Hello'])
            ->assertRedirect('/messages/pAnna')
            ->assertSessionHas('success');
        $this->assertCount(1, $this->commits);
    }

    // ---- helpers ------------------------------------------------------------

    private function user(string $role, ?string $email = null): User
    {
        return User::create([
            'name' => ucfirst($role).' User',
            'email' => $email ?? $role.Str::random(5).'@rehabplus.com',
            'password' => bcrypt('secret123'),
            'role' => $role,
            'is_active' => true,
        ]);
    }

    private function fakeGoogle(Request $r)
    {
        $url = urldecode($r->url());
        $body = $r->data();

        if (str_contains($url, 'identitytoolkit')) {
            $uid = $this->authUsers[$body['email'][0]] ?? null;

            return Http::response($uid ? ['users' => [['localId' => $uid]]] : []);
        }

        if (str_contains($url, 'fcm.googleapis.com')) {
            $this->pushes[] = $body['message'];

            return $body['message']['token'] === 'deadToken'
                ? Http::response(['error' => ['status' => 'NOT_FOUND', 'details' => [['errorCode' => 'UNREGISTERED']]]], 404)
                : Http::response(['name' => 'projects/x/messages/1']);
        }

        $path = trim(Str::after($url, self::ROOT), '/');

        if (str_ends_with($path, ':commit')) {
            $this->commits[] = $body['writes'];

            return Http::response(['writeResults' => []]);
        }

        if (str_ends_with($path, ':batchGet')) {
            return Http::response(array_map(function ($name) {
                $p = Str::after($name, self::ROOT.'/');

                return isset($this->docs[$p]) ? ['found' => $this->restDoc($p)] : ['missing' => $name];
            }, $body['documents']));
        }

        if (str_ends_with($path, ':runQuery')) {
            return Http::response($this->runQuery(Str::before($path, ':runQuery'), $body['structuredQuery']));
        }

        if ($r->method() === 'DELETE') {
            $this->deleted[] = $path;

            return Http::response([]);
        }

        return isset($this->docs[$path]) ? Http::response($this->restDoc($path)) : Http::response(['error' => ['code' => 404]], 404);
    }

    private function runQuery(string $parent, array $q): array
    {
        $prefix = ($parent === '' ? '' : $parent.'/').$q['from'][0]['collectionId'].'/';
        $filter = $q['where']['fieldFilter'] ?? null;

        $rows = collect($this->docs)
            ->filter(fn ($f, $p) => str_starts_with($p, $prefix) && ! str_contains(Str::after($p, $prefix), '/'))
            ->filter(fn ($f) => ! $filter || ($f[$filter['field']['fieldPath']] ?? null) === $filter['value']['stringValue']);

        if (isset($q['orderBy'])) {
            $field = $q['orderBy'][0]['field']['fieldPath'];
            $rows = $q['orderBy'][0]['direction'] === 'DESCENDING' ? $rows->sortByDesc($field) : $rows->sortBy($field);
        }

        return $rows->keys()->map(fn ($p) => ['document' => $this->restDoc($p)])->values()->all() ?: [['readTime' => now()->toIso8601String()]];
    }

    private function restDoc(string $path): array
    {
        return ['name' => self::ROOT.'/'.$path, 'fields' => app(FirestoreClient::class)->encodeFields($this->docs[$path])];
    }
}
