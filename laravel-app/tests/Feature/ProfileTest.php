<?php

namespace Tests\Feature;

use Illuminate\Http\UploadedFile;
use Tests\Support\FakeFirebase;
use Tests\TestCase;

/** My Profile: every staff member edits their own name and picture; role is never changed here. */
class ProfileTest extends TestCase
{
    use FakeFirebase;

    public function test_guests_are_sent_to_login(): void
    {
        $this->get('/profile')->assertRedirect('/login');
    }

    public function test_my_profile_is_in_the_sidebar_below_staff_accounts_and_shows_the_account(): void
    {
        $this->actingAs($this->staff('therapist', 'thA', 'Dr. Ana'))->get('/profile')->assertOk()
            ->assertSee('My Profile')
            ->assertSee('Dr. Ana')
            ->assertSee('Physical Therapist')
            ->assertSee('thA@rehabplus.com')
            ->assertSee('href="http://localhost/profile"', false)
            ->assertDontSee('href="http://localhost/users"', false);
    }

    public function test_name_is_saved_and_the_role_cannot_be_changed(): void
    {
        $this->staff('therapist', 'thA', 'Dr. Ana');

        $this->actingAs($this->staff('therapist', 'thA', 'Dr. Ana'))
            ->put('/profile', ['name' => 'Dr. Ana Reyes', 'role' => 'admin'])
            ->assertRedirect('/profile')
            ->assertSessionHas('success');

        $this->assertSame('Dr. Ana Reyes', $this->docs['users/thA']['name']);
        $this->assertSame('therapist', $this->docs['users/thA']['role']);
        $this->assertSame('Dr. Ana Reyes', $this->authUsers['thA@rehabplus.com']['displayName']);
    }

    public function test_a_picture_is_saved_in_the_user_document_and_shown_on_the_home_board(): void
    {
        $this->staff('staff', 'st1', 'Sam Front');
        $photo = UploadedFile::fake()->image('me.jpg', 200, 200);

        $this->actingAs($this->staff('staff', 'st1', 'Sam Front'))
            ->put('/profile', ['name' => 'Sam Front', 'photo' => $photo])
            ->assertRedirect('/profile');

        $this->assertStringStartsWith('data:image/jpeg;base64,', $this->docs['users/st1']['photoUrl']);

        $this->actingAs($this->staff('admin'))->get('/home')->assertOk()
            ->assertSee('src="data:image/jpeg;base64,', false);
    }

    public function test_pictures_must_be_jpg_png_or_webp_and_500_kb_or_smaller(): void
    {
        $this->staff('staff', 'st1', 'Sam Front');
        $actor = $this->staff('staff', 'st1', 'Sam Front');

        $this->actingAs($actor)->put('/profile', ['name' => 'Sam Front', 'photo' => UploadedFile::fake()->create('cv.pdf', 10, 'application/pdf')])
            ->assertSessionHasErrors('photo');

        $this->actingAs($actor)->put('/profile', ['name' => 'Sam Front', 'photo' => UploadedFile::fake()->image('big.jpg', 200, 200)->size(600)])
            ->assertSessionHasErrors('photo');

        $this->assertArrayNotHasKey('photoUrl', $this->docs['users/st1']);
    }

    public function test_remove_picture_clears_it(): void
    {
        $actor = $this->staff('staff', 'st1', 'Sam Front');
        $this->docs['users/st1']['photoUrl'] = 'data:image/png;base64,iVBORw0KGgo=';

        $this->actingAs($actor)
            ->put('/profile', ['name' => 'Sam Front', 'remove_photo' => 1])
            ->assertRedirect('/profile');

        $this->assertSame('', $this->docs['users/st1']['photoUrl']);
    }

    public function test_the_page_has_no_way_to_edit_another_account(): void
    {
        $this->staff('therapist', 'thB', 'Dr. Ben');

        $this->actingAs($this->staff('therapist', 'thA', 'Dr. Ana'))
            ->put('/profile', ['name' => 'Hijacked', 'uid' => 'thB'])
            ->assertRedirect('/profile');

        $this->assertSame('Dr. Ben', $this->docs['users/thB']['name']);
        $this->assertSame('Hijacked', $this->docs['users/thA']['name']);
    }
}
