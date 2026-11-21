<?php

namespace Tests\Feature;

use Carbon\CarbonImmutable;
use Tests\Support\FakeFirebase;
use Tests\TestCase;

/** The "Patient status" card on Reports & Analytics: pick one patient you can see and read their status. */
class PatientStatusReportTest extends TestCase
{
    use FakeFirebase;

    protected function setUp(): void
    {
        parent::setUp();

        $this->staff('admin');
        $this->staff('therapist', 'thA', 'Dr. Ana');
        $this->staff('therapist', 'thB', 'Dr. Ben');
        $this->patientDoc('pOne', ['name' => 'Olive One', 'condition' => 'ACL', 'therapistId' => 'thA', 'therapistName' => 'Dr. Ana']);
        $this->patientDoc('pTwo', ['name' => 'Tom Two', 'condition' => 'Shoulder', 'therapistId' => 'thB', 'therapistName' => 'Dr. Ben']);

        $this->docs['patients/pOne/prescriptions/rx1'] = ['exerciseType' => 'kneeExtension', 'exerciseName' => 'Knee Extension', 'targetReps' => 10, 'frequencyPerWeek' => 3, 'active' => true, 'startDate' => CarbonImmutable::now()->subDays(20)->toDateString(), 'durationWeeks' => 4];
        $this->docs['patients/pOne/sessions/s1'] = ['exerciseId' => 'kneeExtension', 'prescriptionId' => 'rx1', 'startTime' => CarbonImmutable::now()->subDays(1), 'overallCompliance' => 0.8, 'painLevel' => 4, 'endedEarly' => false, 'outsideSchedule' => false];
        $this->docs['patients/pOne/sessions/s2'] = ['exerciseId' => 'kneeExtension', 'prescriptionId' => 'rx1', 'startTime' => CarbonImmutable::now()->subDays(2), 'overallCompliance' => 0.6, 'painLevel' => 2, 'endedEarly' => true, 'outsideSchedule' => false];
        $this->docs['patients/pOne/goals/g1'] = ['title' => 'Walk 1km', 'status' => 'achieved', 'progress' => 100, 'createdAt' => CarbonImmutable::now()];
    }

    public function test_the_picker_lists_the_patients_the_user_can_see(): void
    {
        $this->actingAs($this->staff('therapist', 'thA', 'Dr. Ana'))->get('/analytics')->assertOk()
            ->assertSee('Patient status')
            ->assertSee('Olive One')
            ->assertDontSee('Tom Two');
    }

    public function test_choosing_a_patient_shows_their_status(): void
    {
        $this->actingAs($this->staff('therapist', 'thA', 'Dr. Ana'))->get('/analytics?patient=pOne')->assertOk()
            ->assertSee('Olive One')
            ->assertSee('Movement accuracy')
            ->assertSee('70%')          // (0.8 + 0.6) / 2
            ->assertSee('3/10')         // average pain of the two sessions (4 and 2)
            ->assertSee('1 ended early')
            ->assertSee('100%')         // the only goal is achieved
            ->assertSee('Open full profile');
    }

    public function test_a_patient_outside_the_users_list_is_not_shown(): void
    {
        $this->actingAs($this->staff('therapist', 'thA', 'Dr. Ana'))->get('/analytics?patient=pTwo')->assertOk()
            ->assertSee("That patient isn't on your list", false)
            ->assertDontSee('Tom Two');
    }

    public function test_an_administrator_can_see_any_patient(): void
    {
        $this->actingAs($this->staff('admin'))->get('/analytics?patient=pTwo')->assertOk()
            ->assertSee('Tom Two')
            ->assertSee('Shoulder');
    }

    public function test_without_a_choice_it_asks_for_one(): void
    {
        $this->actingAs($this->staff('admin'))->get('/analytics')->assertOk()
            ->assertSee('Pick a patient to see their adherence');
    }
}
