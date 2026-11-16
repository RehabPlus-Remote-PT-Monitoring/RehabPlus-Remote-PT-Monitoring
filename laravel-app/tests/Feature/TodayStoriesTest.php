<?php

namespace Tests\Feature;

use Carbon\CarbonImmutable;
use Illuminate\Http\UploadedFile;
use Tests\Support\FakeFirebase;
use Tests\TestCase;

/** "Today at Rehab+": pictures posted as stories from the dashboard, and the featured schedules. */
class TodayStoriesTest extends TestCase
{
    use FakeFirebase;

    protected function setUp(): void
    {
        parent::setUp();

        $this->staff('admin');
        $this->staff('therapist', 'thA', 'Dr. Ana');
    }

    /** The stories listed in the page's data, as decoded JSON. */
    private function storiesOnPage(): array
    {
        $html = $this->get('/')->assertOk()->getContent();
        preg_match('#<script type="application/json" id="stories-data">(.*?)</script>#s', $html, $match);

        return json_decode(html_entity_decode($match[1] ?? '[]'), true) ?: [];
    }

    public function test_the_featured_schedules_show_under_the_logo(): void
    {
        $this->get('/')->assertOk()
            ->assertSee('Today at Rehab+')
            ->assertSee('Pilates schedule')
            ->assertSee('Private class schedule')
            ->assertSee('assets/images/stories/pilates-schedule-tuesday.jpg', false);
    }

    public function test_an_administrator_posts_a_story_with_its_picture(): void
    {
        $this->actingAs($this->staff('admin'))->post('/announcements', [
            'title' => 'Today: strength session',
            'body' => 'Our PT team in the studio this afternoon.',
            'story' => '1',
            'image' => UploadedFile::fake()->image('session.jpg', 400, 300),
        ])->assertRedirect('/announcements');

        $story = array_values($this->docsLike('announcements/*'))[0];
        $this->assertTrue($story['story']);
        $this->assertStringStartsWith('data:image/', $story['imageUrl']);

        $titles = array_column($this->storiesOnPage(), 'title');
        $this->assertContains('Today: strength session', $titles);
    }

    public function test_a_story_can_go_up_with_a_title_and_picture_only(): void
    {
        $this->actingAs($this->staff('admin'))->post('/announcements', [
            'title' => 'Pilates schedule, Tuesday',
            'story' => '1',
            'image' => UploadedFile::fake()->image('schedule.jpg', 400, 600),
        ])->assertSessionHasNoErrors()->assertRedirect('/announcements');

        $this->assertCount(1, $this->docsLike('announcements/*'));
    }

    public function test_the_dashboard_button_says_post_and_the_story_section_is_on_the_announcements_page(): void
    {
        $this->actingAs($this->staff('admin'))->get('/dashboard')->assertOk()
            ->assertSee('Post');

        $this->actingAs($this->staff('admin'))->get('/announcements')->assertOk()
            ->assertSee('Post to Today at Rehab+');
    }

    public function test_a_story_needs_a_picture(): void
    {
        $this->actingAs($this->staff('admin'))->post('/announcements', [
            'title' => 'Today: strength session',
            'body' => 'No picture here.',
            'story' => '1',
        ])->assertSessionHasErrors(['image' => 'A story needs a picture.']);

        $this->assertCount(0, $this->docsLike('announcements/*'));
    }

    public function test_an_announcement_that_is_not_a_story_stays_out_of_the_row(): void
    {
        $this->actingAs($this->staff('admin'))->post('/announcements', [
            'title' => 'Clinic closed on November 1',
            'body' => 'The clinic is closed for the holiday.',
        ])->assertRedirect('/announcements');

        $titles = array_column($this->storiesOnPage(), 'title');
        $this->assertNotContains('Clinic closed on November 1', $titles);
    }

    public function test_an_archived_or_expired_story_is_not_shown(): void
    {
        $picture = 'data:image/jpeg;base64,'.base64_encode('x');
        $this->docs['announcements/old'] = ['title' => 'Expired story', 'body' => 'x', 'story' => true, 'imageUrl' => $picture, 'showUntil' => CarbonImmutable::now()->subDay()->toDateString(), 'postedAt' => CarbonImmutable::now()];
        $this->docs['announcements/gone'] = ['title' => 'Archived story', 'body' => 'x', 'story' => true, 'archived' => true, 'imageUrl' => $picture, 'postedAt' => CarbonImmutable::now()];
        $this->docs['announcements/live'] = ['title' => 'Live story', 'body' => 'x', 'story' => true, 'imageUrl' => $picture, 'postedAt' => CarbonImmutable::now()];

        $titles = array_column($this->storiesOnPage(), 'title');
        $this->assertContains('Live story', $titles);
        $this->assertNotContains('Expired story', $titles);
        $this->assertNotContains('Archived story', $titles);
    }
}
