<?php

namespace Tests\Feature;

use Carbon\CarbonImmutable;
use Illuminate\Http\UploadedFile;
use Tests\Support\FakeFirebase;
use Tests\TestCase;

/** Clinic announcements: administrators post and remove them; everyone sees the current ones. */
class AnnouncementTest extends TestCase
{
    use FakeFirebase;

    public function test_only_administrators_can_open_post_or_remove_announcements(): void
    {
        $staff = $this->staff('therapist', 'thA', 'Dr. Ana');
        $this->docs['announcements/a1'] = ['title' => 'Notice', 'body' => 'Hello', 'postedAt' => CarbonImmutable::now()];

        $this->actingAs($staff)->get('/announcements')->assertForbidden();
        $this->actingAs($staff)->post('/announcements', ['title' => 'Nope', 'body' => 'Nope'])->assertForbidden();
        $this->actingAs($staff)->delete('/announcements/a1')->assertForbidden();

        $this->assertArrayHasKey('announcements/a1', $this->docs);
        $this->assertSame([], array_filter($this->commits));
    }

    public function test_admin_posts_an_announcement_with_a_picture_that_everyone_sees(): void
    {
        $admin = $this->staff('admin', 'adm1', 'Ada Admin');
        $picture = UploadedFile::fake()->image('closed.jpg', 900, 900);

        $this->actingAs($admin)->post('/announcements', [
            'title' => 'Clinic closed on November 1-2',
            'body' => "We will be closed for All Saints' Day.\nRegular operations resume November 3.",
            'image' => $picture,
        ])->assertRedirect('/announcements')->assertSessionHas('success');

        $doc = array_values($this->docsLike('announcements/*'))[0];
        $this->assertSame('Clinic closed on November 1-2', $doc['title']);
        $this->assertSame('Ada Admin', $doc['postedByName']);
        $this->assertStringStartsWith('data:image/jpeg;base64,', $doc['imageUrl']);

        // Shown on the Home page and the welcome page, not on the dashboard.
        $this->actingAs($this->staff('therapist', 'thA', 'Dr. Ana'))->get('/dashboard')->assertOk()
            ->assertDontSee('Clinic closed on November 1-2');
        $this->app['auth']->forgetGuards(); // a visitor, not the signed-in staff member
        $this->get('/')->assertOk()
            ->assertSee('Clinic closed on November 1-2')
            ->assertSee('Announcements')
            ->assertSee('href="http://localhost#announcements"', false);
    }

    public function test_the_post_button_is_only_on_the_dashboard_for_administrators(): void
    {
        $this->actingAs($this->staff('admin'))->get('/dashboard')->assertOk()
            ->assertSee('href="http://localhost/announcements"', false);

        $this->actingAs($this->staff('therapist', 'thA', 'Dr. Ana'))->get('/dashboard')->assertOk()
            ->assertDontSee('href="http://localhost/announcements"', false);
    }

    public function test_expired_announcements_are_hidden_and_today_is_still_shown(): void
    {
        $this->docs['announcements/old'] = [
            'title' => 'Last week notice', 'body' => 'Old', 'showUntil' => now()->subDay()->toDateString(),
            'postedAt' => CarbonImmutable::now()->subDays(3),
        ];
        $this->docs['announcements/today'] = [
            'title' => 'Today only notice', 'body' => 'Current', 'showUntil' => now()->toDateString(),
            'postedAt' => CarbonImmutable::now(),
        ];

        $this->get('/')->assertOk()
            ->assertSee('Today only notice')
            ->assertDontSee('Last week notice');
    }

    public function test_a_show_until_date_in_the_past_is_refused(): void
    {
        $this->actingAs($this->staff('admin'))->post('/announcements', [
            'title' => 'Old news', 'body' => 'Already over', 'show_until' => now()->subDay()->toDateString(),
        ])->assertSessionHasErrors('show_until');

        $this->assertSame([], $this->docsLike('announcements/*'));
    }

    public function test_pictures_must_be_jpg_png_or_webp(): void
    {
        $this->actingAs($this->staff('admin'))->post('/announcements', [
            'title' => 'Document', 'body' => 'Not a picture',
            'image' => UploadedFile::fake()->create('notes.pdf', 20, 'application/pdf'),
        ])->assertSessionHasErrors('image');

        $this->assertSame([], $this->docsLike('announcements/*'));
    }

    public function test_admin_removes_an_announcement(): void
    {
        $this->docs['announcements/a1'] = ['title' => 'Notice', 'body' => 'Hello', 'postedAt' => CarbonImmutable::now()];

        $this->actingAs($this->staff('admin'))->delete('/announcements/a1')
            ->assertRedirect('/announcements')
            ->assertSessionHas('success');

        $this->assertArrayNotHasKey('announcements/a1', $this->docs);
    }
}
