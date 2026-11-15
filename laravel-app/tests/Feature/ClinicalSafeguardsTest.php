<?php

namespace Tests\Feature;

use Carbon\CarbonImmutable;
use Tests\Support\FakeFirebase;
use Tests\TestCase;

/**
 * Clinical safeguards on the dashboard (API_CONTRACT.md "Clinical safeguards"):
 * the completion target on prescriptions, restricted exercises, the clinical &
 * dietary profile, the tolerance review flag and the physician clearance.
 */
class ClinicalSafeguardsTest extends TestCase
{
    use FakeFirebase;

    protected function setUp(): void
    {
        parent::setUp();

        $this->patientDoc('pOne', ['name' => 'Olive One', 'therapistId' => 'thA', 'therapistName' => 'Dr. Ana']);
        $this->patientDoc('pTwo', ['name' => 'Tom Two', 'therapistId' => 'thB']);
        $this->docs['patients/pOne/devices/tok1'] = ['token' => 'tok1'];
    }

    private function therapist()
    {
        return $this->staff('therapist', 'thA', 'Dr. Ana');
    }

    private function rx(string $id, array $fields = []): void
    {
        $this->docs["patients/pOne/prescriptions/{$id}"] = $fields + [
            'exerciseType' => 'kneeExtension', 'targetReps' => 10, 'frequencyPerWeek' => 3,
            'active' => true, 'assignedBy' => 'thA', 'requiredSessions' => 2,
            'createdAt' => CarbonImmutable::now()->subDays(20),
        ];
    }

    /** A session the way the app writes it. */
    private function sessionDoc(string $id, ?string $prescriptionId, array $fields = []): void
    {
        $this->docs["patients/pOne/sessions/{$id}"] = $fields + [
            'exerciseId' => 'kneeExtension', 'exerciseName' => 'Knee Extension', 'prescriptionId' => $prescriptionId,
            'startTime' => CarbonImmutable::now()->subDays(2), 'completedReps' => 10, 'targetReps' => 10,
            'overallCompliance' => 0.9, 'painLevel' => 2, 'endedEarly' => false, 'outsideSchedule' => false,
        ];
    }

    private function profile(array $fields): void
    {
        $this->docs['patients/pOne/clinical/profile'] = $fields + ['validatedBy' => 'thA', 'validatedByName' => 'Dr. Ana', 'validatedAt' => CarbonImmutable::now()->subDay()];
    }

    private function clearanceForm(array $overrides = []): array
    {
        return $overrides + [
            'decision' => 'cleared',
            'physician_name' => 'Dr. Paolo Reyes',
            'physician_license' => '0123456',
            'assessed_at' => CarbonImmutable::now(config('app.timezone'))->toDateString(),
            'findings' => 'Full range of motion, no pain on loading.',
            'recommendations' => 'Return to normal activity.',
            'attested' => '1',
        ];
    }

    // ---- Prescriptions: completion target ------------------------------------

    public function test_required_sessions_is_written_on_create_and_cleared_on_edit(): void
    {
        $user = $this->therapist();

        $this->actingAs($user)->post('/patients/pOne/prescriptions', [
            'exercise_type' => 'kneeExtension', 'target_reps' => 10, 'frequency_per_week' => 3, 'required_sessions' => 12,
        ])->assertRedirect('/patients/pOne')->assertSessionHasNoErrors();

        $id = array_key_first($this->docsLike('patients/pOne/prescriptions/*'));
        $this->assertSame(['integerValue' => '12'], $this->commits[0][0]['update']['fields']['requiredSessions']);
        $this->assertSame(12, $this->docs[$id]['requiredSessions']);

        // Blank on edit: written as null (contract: same as omitted), so the target is removed.
        $rxId = basename($id);
        $this->actingAs($user)->put("/patients/pOne/prescriptions/{$rxId}", [
            'exercise_type' => 'kneeExtension', 'target_reps' => 10, 'frequency_per_week' => 3, 'required_sessions' => '',
        ])->assertRedirect('/patients/pOne');

        $this->assertContains('requiredSessions', $this->commits[1][0]['updateMask']['fieldPaths']);
        $this->assertNull($this->docs[$id]['requiredSessions']);
    }

    public function test_required_sessions_is_validated(): void
    {
        $user = $this->therapist();
        foreach ([0, 501, 'many', 2.5] as $bad) {
            $this->actingAs($user)->post('/patients/pOne/prescriptions', [
                'exercise_type' => 'kneeExtension', 'target_reps' => 10, 'frequency_per_week' => 3, 'required_sessions' => $bad,
            ])->assertSessionHasErrors('required_sessions');
        }
        $this->assertSame([], $this->commits);
    }

    public function test_form_and_patient_page_show_the_completion_target(): void
    {
        $this->rx('rx1', ['requiredSessions' => 3]);
        $this->sessionDoc('s1', 'rx1');
        $this->sessionDoc('s2', 'rx1', ['endedEarly' => true]);
        $user = $this->therapist();

        $this->actingAs($user)->get('/patients/pOne/prescriptions/rx1/edit')
            ->assertOk()
            ->assertSee('Sessions to complete')
            ->assertSee('Finished sessions needed before this exercise counts as complete; required before clearance')
            ->assertSee('name="required_sessions"', false)
            ->assertSee('value="3"', false);

        $this->actingAs($user)->get('/patients/pOne')
            ->assertOk()
            ->assertSee('1/3 finished');
    }

    // ---- Prescriptions: restricted exercises --------------------------------

    public function test_a_restricted_exercise_cannot_be_assigned(): void
    {
        $this->profile(['restrictedExercises' => ['wallSit']]);

        $this->actingAs($this->therapist())->post('/patients/pOne/prescriptions', [
            'exercise_type' => 'wallSit', 'target_reps' => 3, 'frequency_per_week' => 3,
        ])->assertSessionHasErrors(['exercise_type' => 'Wall Sit is restricted by the clinician in this patient\'s clinical profile, so it can\'t be assigned or resumed. Change the clinical profile first if that is no longer the case.']);

        $this->assertSame([], $this->commits);
        $this->assertSame([], $this->pushes);
    }

    public function test_a_prescription_cannot_be_edited_to_a_restricted_exercise(): void
    {
        $this->profile(['restrictedExercises' => ['wallSit']]);
        $this->rx('rx1');

        $this->actingAs($this->therapist())->put('/patients/pOne/prescriptions/rx1', [
            'exercise_type' => 'wallSit', 'target_reps' => 3, 'frequency_per_week' => 3,
        ])->assertSessionHasErrors('exercise_type');

        $this->assertSame([], $this->commits);
        $this->assertSame('kneeExtension', $this->docs['patients/pOne/prescriptions/rx1']['exerciseType']);
    }

    public function test_a_restricted_prescription_cannot_be_resumed_but_can_be_stopped(): void
    {
        $this->profile(['restrictedExercises' => ['wallSit']]);
        $this->rx('rxStopped', ['exerciseType' => 'wallSit', 'active' => false]);
        $this->rx('rxActive', ['exerciseType' => 'wallSit']);
        $user = $this->therapist();

        $this->actingAs($user)->post('/patients/pOne/prescriptions/rxStopped/active', ['active' => 1])
            ->assertRedirect('/patients/pOne')
            ->assertSessionHasErrors('active');
        $this->assertSame([], $this->commits);
        $this->assertFalse($this->docs['patients/pOne/prescriptions/rxStopped']['active']);

        $this->actingAs($user)->post('/patients/pOne/prescriptions/rxActive/active', ['active' => 0])
            ->assertRedirect('/patients/pOne')->assertSessionHasNoErrors();
        $this->assertFalse($this->docs['patients/pOne/prescriptions/rxActive']['active']);
    }

    public function test_patient_page_marks_active_restricted_prescriptions(): void
    {
        $this->profile(['restrictedExercises' => ['wallSit']]);
        $this->rx('rx1', ['exerciseType' => 'wallSit']);
        $this->rx('rx2', ['exerciseType' => 'bicepCurl']);

        $html = $this->actingAs($this->therapist())->get('/patients/pOne')->assertOk()->getContent();

        $this->assertSame(1, substr_count($html, '</i>Restricted by clinician</span></div>'), 'only the active restricted prescription row');
        $this->assertStringContainsString('Wall Sit: restricted by clinician, adjust the program', $html);
    }

    // ---- Clinical & dietary profile ----------------------------------------

    public function test_saving_the_profile_writes_the_contract_fields(): void
    {
        $user = $this->therapist();
        $this->actingAs($user)->get('/patients/pOne/clinical-profile/edit')
            ->assertOk()
            ->assertSee('Dietary information is context only; it never changes the exercise program. Only the clinician\'s restrictions and tolerance flag do.', false)
            ->assertSee('Poor appetite / undernourished')
            ->assertSee('Standing Hip Abduction');

        $this->actingAs($user)->put('/patients/pOne/clinical-profile', [
            'precautions' => '  Avoid deep knee bends.  ',
            'dietary_notes' => 'Low salt.',
            'nutrition_flags' => ['hypertension', 'diabetes'],
            'restricted_exercises' => ['wallSit', 'miniSquat'],
            'low_tolerance' => '1',
            'tolerance_note' => 'Tires quickly.',
            'next_reassessment_at' => CarbonImmutable::now(config('app.timezone'))->addMonth()->toDateString(),
        ])->assertRedirect('/patients/pOne#clinical-profile')->assertSessionHasNoErrors();

        $this->assertCount(1, $this->commits);
        $write = $this->commits[0][0];
        $this->assertSame(self::ROOT.'/patients/pOne/clinical/profile', $write['update']['name']);
        $this->assertArrayNotHasKey('currentDocument', $write, 'a merge: creates the doc or overwrites it');
        $this->assertSame([['fieldPath' => 'validatedAt', 'setToServerValue' => 'REQUEST_TIME']], $write['updateTransforms']);
        $this->assertEqualsCanonicalizing([
            'precautions', 'dietaryNotes', 'nutritionFlags', 'restrictedExercises', 'lowTolerance',
            'toleranceNote', 'validatedBy', 'validatedByName', 'nextReassessmentAt',
        ], $write['updateMask']['fieldPaths']);

        $doc = $this->docs['patients/pOne/clinical/profile'];
        $this->assertSame('Avoid deep knee bends.', $doc['precautions']);
        $this->assertSame('Low salt.', $doc['dietaryNotes']);
        $this->assertSame(['diabetes', 'hypertension'], $doc['nutritionFlags'], 'contract order, each once');
        $this->assertSame(['wallSit', 'miniSquat'], $doc['restrictedExercises'], 'catalog order');
        $this->assertTrue($doc['lowTolerance']);
        $this->assertSame('Tires quickly.', $doc['toleranceNote']);
        $this->assertSame('thA', $doc['validatedBy']);
        $this->assertSame('Dr. Ana', $doc['validatedByName']);
        $this->assertInstanceOf(CarbonImmutable::class, $doc['validatedAt']);
        $this->assertSame('00:00', $doc['nextReassessmentAt']->setTimezone(config('app.timezone'))->format('H:i'), 'start of the day, clinic time');

        $this->actingAs($user)->get('/patients/pOne')
            ->assertOk()
            ->assertSee('data-clinical-profile="ok"', false)
            ->assertSee('Dietary information is context only; it never changes the exercise program. Only the clinician\'s restrictions and tolerance flag do.', false)
            ->assertSee('Avoid deep knee bends.')
            ->assertSee('Low tolerance')
            ->assertSee('Hypertension')
            ->assertSee('Validated by Dr. Ana');
    }

    public function test_unticking_everything_clears_the_lists_and_tolerance(): void
    {
        $this->profile(['restrictedExercises' => ['wallSit'], 'nutritionFlags' => ['anemia'], 'lowTolerance' => true, 'nextReassessmentAt' => CarbonImmutable::now()->addWeek()]);

        $this->actingAs($this->therapist())->put('/patients/pOne/clinical-profile', ['low_tolerance' => '0'])
            ->assertRedirect('/patients/pOne#clinical-profile');

        $doc = $this->docs['patients/pOne/clinical/profile'];
        $this->assertSame([], $doc['restrictedExercises']);
        $this->assertSame([], $doc['nutritionFlags']);
        $this->assertFalse($doc['lowTolerance']);
        $this->assertNull($doc['nextReassessmentAt']);
        $this->assertSame('', $doc['precautions']);
    }

    public function test_profile_validation(): void
    {
        $user = $this->therapist();
        $this->actingAs($user)->put('/patients/pOne/clinical-profile', ['nutrition_flags' => ['vegan']])->assertSessionHasErrors('nutrition_flags.0');
        $this->actingAs($user)->put('/patients/pOne/clinical-profile', ['restricted_exercises' => ['jumpingJacks']])->assertSessionHasErrors('restricted_exercises.0');
        $this->actingAs($user)->put('/patients/pOne/clinical-profile', ['precautions' => str_repeat('a', 1001)])->assertSessionHasErrors('precautions');
        $this->actingAs($user)->put('/patients/pOne/clinical-profile', ['tolerance_note' => str_repeat('a', 501)])->assertSessionHasErrors('tolerance_note');
        $this->actingAs($user)->put('/patients/pOne/clinical-profile', ['next_reassessment_at' => '2099-01-01'])->assertSessionHasErrors('next_reassessment_at');
        $this->assertSame([], $this->commits);
    }

    public function test_a_corrupt_profile_doc_does_not_break_the_page(): void
    {
        $this->docs['patients/pOne/clinical/profile'] = [
            'precautions' => ['not' => 'text'], 'nutritionFlags' => 'diabetes', 'restrictedExercises' => [['x' => 1], 'wallSit', 'nope'],
            'lowTolerance' => 'yes', 'validatedAt' => 'yesterday', 'validatedByName' => ['a'],
        ];

        $this->actingAs($this->therapist())->get('/patients/pOne')
            ->assertOk()
            ->assertSee('data-clinical-profile="ok"', false)
            ->assertSee('Wall Sit')
            ->assertDontSee('Low tolerance');
    }

    public function test_an_unreadable_profile_shows_unavailable_and_the_page_still_loads(): void
    {
        $this->rx('rx1', ['requiredSessions' => 1]);
        $this->sessionDoc('s1', 'rx1');
        $this->injectedFailures['clinical/profile'] = array_fill(0, 10, 'connection');

        $this->actingAs($this->therapist())->get('/patients/pOne')
            ->assertOk()
            ->assertSee('Clinical profile unavailable')
            ->assertSee('data-gate="unavailable"', false)
            ->assertSee('Assigned exercises')
            ->assertSee('id="decision_cleared"', false)
            ->assertSee('disabled', false);
    }

    // ---- Tolerance review flag ---------------------------------------------

    public function test_tolerance_review_lists_sessions_for_a_low_tolerance_patient(): void
    {
        $this->profile(['lowTolerance' => true]);
        $this->sessionDoc('sPain6', null, ['painLevel' => 6, 'exerciseName' => 'Pain Six Lift']);
        $this->sessionDoc('sEarly', null, ['endedEarly' => true, 'exerciseName' => 'Stopped Early Lift']);
        $this->sessionDoc('sCalm', null, ['painLevel' => 3, 'exerciseName' => 'Calm Lift']);
        $this->sessionDoc('sOld', null, ['painLevel' => 9, 'exerciseName' => 'Old Lift', 'startTime' => CarbonImmutable::now()->subDays(20)]);

        $this->actingAs($this->therapist())->get('/patients/pOne')
            ->assertOk()
            ->assertSee('data-tolerance-review="flagged"', false)
            ->assertSee('Needs clinician review')
            ->assertSeeInOrder(['Needs clinician review', 'Pain Six Lift', 'Program completion'])
            ->assertSeeInOrder(['Needs clinician review', 'Stopped Early Lift', 'Program completion'])
            ->assertDontSee('Calm Lift · pain')
            ->assertDontSee('Old Lift · pain');
    }

    public function test_without_flags_only_severe_pain_needs_review(): void
    {
        $this->sessionDoc('sPain6', null, ['painLevel' => 6]);
        $this->sessionDoc('sEarly', null, ['endedEarly' => true]);

        $this->actingAs($this->therapist())->get('/patients/pOne')->assertOk()->assertDontSee('Needs clinician review');

        $this->sessionDoc('sPain8', null, ['painLevel' => 8, 'exerciseName' => 'Severe Lift']);
        $this->actingAs($this->therapist())->get('/patients/pOne')->assertOk()
            ->assertSee('Needs clinician review')
            ->assertSee('Severe Lift');
    }

    // ---- Clearance ---------------------------------------------------------

    public function test_cleared_is_refused_while_the_program_is_incomplete_and_nothing_is_written(): void
    {
        $this->rx('rx1', ['requiredSessions' => 3]);
        $this->rx('rx2', ['exerciseType' => 'bicepCurl', 'requiredSessions' => null]);
        $this->sessionDoc('s1', 'rx1');
        $this->sessionDoc('s2', 'rx1', ['endedEarly' => true]);

        $this->actingAs($this->therapist())->from('/patients/pOne')->post('/patients/pOne/clearances', $this->clearanceForm())
            ->assertRedirect('/patients/pOne#clearance')
            ->assertSessionHasErrors('decision');

        $message = session('errors')->first('decision');
        $this->assertStringContainsString('Knee Extension: 1/3 sessions finished', $message);
        $this->assertStringContainsString('Bicep Curl: no completion target set', $message);
        $this->assertSame([], $this->commits);
        $this->assertSame([], $this->docsLike('patients/pOne/clearances/*'));
        $this->assertSame([], $this->docsLike('patients/pOne/notifications/*'));
        $this->assertSame([], $this->pushes);
    }

    public function test_cleared_is_refused_with_no_program(): void
    {
        $this->actingAs($this->therapist())->post('/patients/pOne/clearances', $this->clearanceForm())
            ->assertSessionHasErrors('decision');
        $this->assertStringContainsString('no active exercises', session('errors')->first('decision'));
        $this->assertSame([], $this->commits);
    }

    public function test_cleared_is_refused_when_a_met_prescription_is_restricted(): void
    {
        $this->rx('rx1', ['requiredSessions' => 1]);
        $this->sessionDoc('s1', 'rx1');
        $this->profile(['restrictedExercises' => ['kneeExtension']]);

        $this->actingAs($this->therapist())->post('/patients/pOne/clearances', $this->clearanceForm())
            ->assertSessionHasErrors('decision');
        $this->assertStringContainsString('restricted by clinician', session('errors')->first('decision'));
        $this->assertSame([], $this->commits);
    }

    public function test_not_cleared_is_allowed_while_incomplete_and_writes_the_snapshot(): void
    {
        $this->rx('rx1', ['requiredSessions' => 3]);
        $this->rx('rxStopped', ['active' => false]);
        $this->sessionDoc('s1', 'rx1');

        $this->actingAs($this->therapist())->post('/patients/pOne/clearances', $this->clearanceForm([
            'decision' => 'not_cleared', 'recommendations' => '',
        ]))->assertRedirect('/patients/pOne#clearance')->assertSessionHasNoErrors()->assertSessionHas('success');

        $this->assertCount(1, $this->commits);
        $this->assertCount(1, $this->commits[0], 'no notification for not_cleared');
        $write = $this->commits[0][0];
        $this->assertSame(['exists' => false], $write['currentDocument'], 'append-only: a new doc each time');
        $this->assertSame([['fieldPath' => 'signedAt', 'setToServerValue' => 'REQUEST_TIME']], $write['updateTransforms']);
        $this->assertMatchesRegularExpression('#/patients/pOne/clearances/[A-Za-z0-9]{20}$#', $write['update']['name']);

        $doc = array_values($this->docsLike('patients/pOne/clearances/*'))[0];
        $this->assertSame('not_cleared', $doc['decision']);
        $this->assertSame('Dr. Paolo Reyes', $doc['physicianName']);
        $this->assertSame('0123456', $doc['physicianLicense']);
        $this->assertSame(CarbonImmutable::now(config('app.timezone'))->startOfDay()->getTimestamp(), $doc['assessedAt']->getTimestamp());
        $this->assertSame('Full range of motion, no pain on loading.', $doc['findings']);
        $this->assertSame('', $doc['recommendations']);
        $this->assertTrue($doc['attested']);
        $this->assertFalse($doc['programComplete']);
        $this->assertSame([['prescriptionId' => 'rx1', 'exerciseType' => 'kneeExtension', 'finished' => 1, 'required' => 3]], $doc['requirements']);
        $this->assertSame('thA', $doc['signedBy']);
        $this->assertSame('Dr. Ana', $doc['signedByName']);
        $this->assertInstanceOf(CarbonImmutable::class, $doc['signedAt']);
        $this->assertSame([], $this->pushes);
    }

    public function test_cleared_when_complete_writes_record_and_notification_then_pushes(): void
    {
        $this->rx('rx1', ['requiredSessions' => 2]);
        $this->rx('rx2', ['exerciseType' => 'wallSit', 'requiredSessions' => 1]);
        $this->sessionDoc('s1', 'rx1');
        $this->sessionDoc('s2', 'rx1');
        $this->sessionDoc('s3', 'rx2');

        $this->actingAs($this->therapist())->post('/patients/pOne/clearances', $this->clearanceForm())
            ->assertRedirect('/patients/pOne#clearance')->assertSessionHasNoErrors();

        $this->assertCount(1, $this->commits);
        [$record, $notification] = $this->commits[0];
        $this->assertSame(['exists' => false], $record['currentDocument']);
        $this->assertSame('cleared', $record['update']['fields']['decision']['stringValue']);
        $this->assertTrue($record['update']['fields']['programComplete']['booleanValue']);

        $doc = array_values($this->docsLike('patients/pOne/clearances/*'))[0];
        $this->assertSame([
            ['prescriptionId' => 'rx1', 'exerciseType' => 'kneeExtension', 'finished' => 2, 'required' => 2],
            ['prescriptionId' => 'rx2', 'exerciseType' => 'wallSit', 'finished' => 1, 'required' => 1],
        ], collect($doc['requirements'])->sortBy('prescriptionId')->values()->all());

        $this->assertSame(['exists' => false], $notification['currentDocument']);
        $this->assertSame([['fieldPath' => 'createdAt', 'setToServerValue' => 'REQUEST_TIME']], $notification['updateTransforms']);
        $fields = $notification['update']['fields'];
        $this->assertSame('progress', $fields['type']['stringValue']);
        $this->assertSame('Medical clearance issued', $fields['title']['stringValue']);
        $this->assertStringContainsString('Dr. Paolo Reyes', $fields['body']['stringValue']);
        $this->assertStringNotContainsStringIgnoringCase('recover', $fields['body']['stringValue']);
        $this->assertFalse($fields['read']['booleanValue']);

        $this->assertCount(1, $this->pushes);
        $this->assertSame(['type' => 'progress'], $this->pushes[0]['data']);
        $this->assertSame('Medical clearance issued', $this->pushes[0]['notification']['title']);

        $this->actingAs($this->therapist())->get('/patients/pOne')
            ->assertOk()
            ->assertSee('data-clearance="cleared"', false)
            ->assertSee('Cleared by Dr. Paolo Reyes');
    }

    public function test_a_failed_push_never_fails_the_saved_clearance(): void
    {
        $this->rx('rx1', ['requiredSessions' => 1]);
        $this->sessionDoc('s1', 'rx1');
        $this->injectedFailures['fcm.googleapis.com'] = ['connection'];

        $this->actingAs($this->therapist())->post('/patients/pOne/clearances', $this->clearanceForm())
            ->assertRedirect('/patients/pOne#clearance')->assertSessionHas('success');

        $this->assertCount(1, $this->docsLike('patients/pOne/clearances/*'));
        $this->assertCount(1, $this->docsLike('patients/pOne/notifications/*'));
    }

    public function test_clearance_validation(): void
    {
        $this->rx('rx1', ['requiredSessions' => 1]);
        $this->sessionDoc('s1', 'rx1');
        $user = $this->therapist();
        $tomorrow = CarbonImmutable::now(config('app.timezone'))->addDay()->toDateString();

        $cases = [
            'attested' => ['attested' => null],
            'assessed_at' => ['assessed_at' => $tomorrow],
            'physician_license' => ['physician_license' => str_repeat('1', 41)],
            'physician_name' => ['physician_name' => '   '],
            'findings' => ['findings' => str_repeat('a', 2001)],
            'recommendations' => ['recommendations' => str_repeat('a', 1001)],
            'decision' => ['decision' => 'recovered'],
        ];
        foreach ($cases as $field => $override) {
            $this->actingAs($user)->post('/patients/pOne/clearances', array_filter($this->clearanceForm($override), fn ($v) => $v !== null))
                ->assertSessionHasErrors($field);
        }
        $this->assertSame([], $this->commits);
    }

    public function test_page_shows_the_gate_and_history_newest_first(): void
    {
        $this->rx('rx1', ['requiredSessions' => 3]);
        $this->sessionDoc('s1', 'rx1');
        $this->docs['patients/pOne/clearances/old'] = [
            'decision' => 'cleared', 'physicianName' => 'Dr. Older', 'physicianLicense' => '111', 'assessedAt' => CarbonImmutable::now()->subDays(30),
            'findings' => 'Older findings', 'recommendations' => '', 'attested' => true, 'programComplete' => true,
            'requirements' => [], 'signedBy' => 'thA', 'signedByName' => 'Dr. Ana', 'signedAt' => CarbonImmutable::now()->subDays(30),
        ];
        $this->docs['patients/pOne/clearances/new'] = [
            'decision' => 'not_cleared', 'physicianName' => 'Dr. Newer', 'physicianLicense' => '222', 'assessedAt' => CarbonImmutable::now()->subDay(),
            'findings' => 'Newer findings', 'recommendations' => 'More work', 'attested' => true, 'programComplete' => false,
            'requirements' => [['prescriptionId' => 'rx1', 'exerciseType' => 'kneeExtension', 'finished' => 1, 'required' => 3]],
            'signedBy' => 'thA', 'signedByName' => 'Dr. Ana', 'signedAt' => CarbonImmutable::now()->subDay(),
        ];
        // A corrupt record is skipped, not shown as either decision.
        $this->docs['patients/pOne/clearances/bad'] = ['decision' => ['cleared'], 'findings' => ['x'], 'signedAt' => CarbonImmutable::now()];

        $this->actingAs($this->therapist())->get('/patients/pOne')
            ->assertOk()
            ->assertSee('Exercise completion')
            ->assertSee('Compliance (form accuracy &amp; adherence)', false)
            ->assertSee('Medical clearance (physician decision)')
            ->assertSee('data-gate="in_progress"', false)
            ->assertSee('Knee Extension: 1/3 sessions finished')
            ->assertSee('data-clearance="not_cleared"', false)
            ->assertSee('Not cleared: continue / revise the program')
            ->assertSeeInOrder(['Clearance history', 'Newer findings', 'Older findings'])
            ->assertDontSee('recovered');
    }

    public function test_cleared_option_is_enabled_only_when_ready(): void
    {
        $this->rx('rx1', ['requiredSessions' => 1]);
        $this->sessionDoc('s1', 'rx1');

        $html = $this->actingAs($this->therapist())->get('/patients/pOne')->assertOk()->getContent();
        $this->assertStringContainsString('data-gate="ready_for_review"', $html);
        $this->assertStringContainsString('Ready for physician assessment.', $html);
        $this->assertDoesNotMatchRegularExpression('/id="decision_cleared"[^>]*disabled/', $html);

        $this->rx('rx2', ['exerciseType' => 'bicepCurl', 'requiredSessions' => null]);
        $html = $this->actingAs($this->therapist())->get('/patients/pOne')->assertOk()->getContent();
        $this->assertMatchesRegularExpression('/id="decision_cleared"[^>]*disabled/', $html);
    }

    // ---- Who may do what ---------------------------------------------------

    public function test_another_therapist_gets_404_and_nothing_is_written(): void
    {
        $this->rx('rx1', ['requiredSessions' => 1]);
        $this->sessionDoc('s1', 'rx1');
        $other = $this->staff('therapist', 'thB', 'Dr. Ben');

        $this->actingAs($other)->get('/patients/pOne/clinical-profile/edit')->assertNotFound();
        $this->actingAs($other)->put('/patients/pOne/clinical-profile', ['precautions' => 'x'])->assertNotFound();
        $this->actingAs($other)->post('/patients/pOne/clearances', $this->clearanceForm())->assertNotFound();
        $this->actingAs($other)->post('/patients/bad.id/clearances', $this->clearanceForm())->assertNotFound();
        $this->assertSame([], $this->commits);
    }

    public function test_front_desk_staff_are_forbidden_and_see_no_clinical_safeguards(): void
    {
        $frontDesk = $this->staff('staff', 'deskUid', 'Desk Person');

        $this->actingAs($frontDesk)->get('/patients/pOne/clinical-profile/edit')->assertForbidden();
        $this->actingAs($frontDesk)->put('/patients/pOne/clinical-profile', ['precautions' => 'x'])->assertForbidden();
        $this->actingAs($frontDesk)->post('/patients/pOne/clearances', $this->clearanceForm(['decision' => 'not_cleared']))->assertForbidden();
        $this->assertSame([], $this->commits);

        $this->actingAs($frontDesk)->get('/patients/pOne')->assertOk()
            ->assertDontSee('Program completion &amp; clearance', false)
            ->assertDontSee('Clinical &amp; dietary profile', false);
    }

    public function test_an_admin_can_sign_for_any_patient(): void
    {
        $this->docs['patients/pTwo/prescriptions/rxT'] = ['exerciseType' => 'kneeExtension', 'targetReps' => 10, 'frequencyPerWeek' => 3, 'active' => true, 'requiredSessions' => 1];
        $this->docs['patients/pTwo/sessions/sT'] = ['prescriptionId' => 'rxT', 'endedEarly' => false, 'startTime' => CarbonImmutable::now()->subDay()];

        $this->actingAs($this->staff('admin'))->post('/patients/pTwo/clearances', $this->clearanceForm())
            ->assertRedirect('/patients/pTwo#clearance')->assertSessionHasNoErrors();

        $doc = array_values($this->docsLike('patients/pTwo/clearances/*'))[0];
        $this->assertSame('adminUid', $doc['signedBy']);
        $this->assertSame('Admin User', $doc['signedByName']);
    }
}
