<?php

namespace Tests\Feature;

use Carbon\CarbonImmutable;
use Tests\Support\FakeFirebase;
use Tests\TestCase;

/**
 * Staff names and photos come from the account as it is now, so a rename or a
 * new picture shows wherever the person appears, not the name saved on a record.
 */
class StaffDirectoryTest extends TestCase
{
    use FakeFirebase;

    public function test_notes_show_the_current_name_after_a_rename(): void
    {
        $this->patientDoc('pOne', ['name' => 'Olive One', 'therapistId' => 'thA', 'therapistName' => 'Dr. Ana']);
        $this->docs['patients/pOne/notes/n1'] = [
            'topic' => 'Progress',
            'text' => 'Doing well',
            'noteDate' => CarbonImmutable::now()->startOfDay(),
            'therapistId' => 'thA',
            'therapistName' => 'Dr. Ana',
            'createdAt' => CarbonImmutable::now(),
        ];
        $this->staff('therapist', 'thA', 'Dr. Ana');

        $this->actingAs($this->staff('therapist', 'thA', 'Dr. Ana'))
            ->put('/profile', ['name' => 'Dr. Ana Reyes'])
            ->assertRedirect('/profile');

        $this->assertSame('Dr. Ana', $this->docs['patients/pOne/notes/n1']['therapistName'], 'the saved record is not rewritten');

        $this->actingAs($this->staff('admin'))->get('/patients/pOne')->assertOk()
            ->assertSee('Doing well')
            ->assertSee('Dr. Ana Reyes');
    }

    public function test_top_bar_shows_the_signed_in_persons_current_photo(): void
    {
        $actor = $this->staff('staff', 'st1', 'Sam Front');
        $this->docs['users/st1']['photoUrl'] = 'data:image/png;base64,iVBORw0KGgo=';

        $this->actingAs($actor)->get('/profile')->assertOk()
            ->assertSee('src="data:image/png;base64,iVBORw0KGgo="', false)
            ->assertSee('user-avatar-photo', false);
    }

    public function test_top_bar_falls_back_to_initials_without_a_photo(): void
    {
        $actor = $this->staff('staff', 'st1', 'Sam Front');

        $this->actingAs($actor)->get('/profile')->assertOk()
            ->assertDontSee('user-avatar-photo', false)
            ->assertSee('<div class="user-avatar">S</div>', false);
    }

    public function test_staff_accounts_list_shows_each_persons_photo(): void
    {
        $this->staff('therapist', 'thA', 'Dr. Ana');
        $this->staff('staff', 'st1', 'Sam Front');
        $this->docs['users/thA']['photoUrl'] = 'data:image/png;base64,iVBORw0KGgo=';

        $this->actingAs($this->staff('admin'))->get('/users')->assertOk()
            ->assertSee('src="data:image/png;base64,iVBORw0KGgo="', false)
            ->assertSee('>S</div>', false);
    }
}
