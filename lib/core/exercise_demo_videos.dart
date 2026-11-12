// lib/core/exercise_demo_videos.dart
import '../models/exercise_model.dart';

/// Short "how to do it properly" demo video for each exercise, shown from the
/// exercise selection page. Every URL must be HTTPS. An exercise with no entry
/// shows its set-up notes and a "coming soon" note instead of a video.
///
/// Direct video files (.mp4, hosted by us) play inside the app.
/// To add one, put the hosted file's URL in the map, for example:
///   ExerciseType.kneeExtension: 'https://example.com/videos/knee_extension.mp4',
const Map<ExerciseType, String> exerciseDemoVideoUrls = {};

/// An outside demo video (YouTube, Physitrack, Prehab Guys). It can't play
/// inside the app, so the sheet opens it in the browser or the YouTube app.
class ExerciseDemoLink {
  const ExerciseDemoLink({
    required this.url,
    this.author,
    this.authorConsent = false,
  });

  /// HTTPS link to the video page.
  final String url;

  /// Name of the video's creator (the presenter or uploader), shown as credit
  /// when known. Null means it hasn't been confirmed yet.
  final String? author;

  /// True only once the creator has given permission for their video to be
  /// linked from this app. Videos without it are hidden, and the sheet shows
  /// the "coming soon" note. Set this to true after you have that permission.
  final bool authorConsent;
}

/// Demo videos on outside platforms, keyed by exercise. Chosen from
/// physiotherapy sources where possible; each one should still be checked
/// against the clinic's own protocol.
const Map<ExerciseType, ExerciseDemoLink> exerciseDemoLinks = {
  // Seated, chair. Physitrack, active knee extension.
  ExerciseType.kneeExtension: ExerciseDemoLink(
    url: 'https://us.physitrack.com/home-exercise-video/seated-knee-extension-(active)',
    author: 'Physitrack',
    authorConsent: true,
  ),
  // Lying on the back. YouTube, "Straight Leg Raise Exercise - How To Do Properly".
  ExerciseType.straightLegRaise: ExerciseDemoLink(
    url: 'https://www.youtube.com/watch?v=EWGR5mTPzsU',
    author: 'Margaret Martin, Physical Therapist',
    authorConsent: true,
  ),
  // Lying face down. YouTube, "Knee Flexion (prone)".
  ExerciseType.kneeFlexion: ExerciseDemoLink(
    url: 'https://www.youtube.com/watch?v=itikHnsM30Y',
    author: 'Dynamic Health & Sports Osteo',
    authorConsent: true,
  ),
  // Lying on the back. YouTube, "Improve Knee Bend - Heel Slides".
  ExerciseType.heelSlide: ExerciseDemoLink(
    url: 'https://www.youtube.com/watch?v=yp-mXRtc_Sw',
    author: 'Knee Replacement Therapists',
    authorConsent: true,
  ),
  // Physitrack, sit-to-stand version 1.
  ExerciseType.sitToStand: ExerciseDemoLink(
    url: 'https://us.physitrack.com/home-exercise-video/sit-to-stand---version-1',
    author: 'Physitrack',
    authorConsent: true,
  ),
  // YouTube, "Glute Bridge 101" (Kevin Sartin, PT).
  ExerciseType.gluteBridge: ExerciseDemoLink(
    url: 'https://www.youtube.com/watch?v=CPb8yRUxWBQ',
    author: 'Kevin Sartin, PT',
    authorConsent: true,
  ),
  // YouTube, "Build Arm Strength Safely with Bicep Curls" (physio demo).
  ExerciseType.bicepCurl: ExerciseDemoLink(
    url: 'https://www.youtube.com/watch?v=k9zWqdy1riw',
    author: 'BioVision 3D',
    authorConsent: true,
  ),
  // Assisted forward elevation (the healthy arm helps). YouTube, Pezzullo PT.
  // Not the unassisted standing raise.
  ExerciseType.forwardRaise: ExerciseDemoLink(
    url: 'https://www.youtube.com/watch?v=xdo0gi77SL0',
    author: 'David J. Pezzullo, PT',
    authorConsent: true,
  ),
  // Gym tutorial, not a physio demo. Replace with a clinic video if you have one.
  ExerciseType.sideRaise: ExerciseDemoLink(
    url: 'https://www.youtube.com/watch?v=U3Atcn3wFjY',
    author: 'Live Lean TV Daily Exercises',
    authorConsent: true,
  ),
  // YouTube, "Mini Squats Exercise for Early Phase Knee and Hip Recovery (Physio)".
  ExerciseType.miniSquat: ExerciseDemoLink(
    url: 'https://www.youtube.com/watch?v=B4V33-8OH_8',
    author: 'good exercise guide',
    authorConsent: true,
  ),
  // Physitrack, standing active hip abduction (beside a chair).
  ExerciseType.hipAbduction: ExerciseDemoLink(
    url: 'https://us.physitrack.com/home-exercise-video/standing-active-hip-abduction',
    author: 'Physitrack',
    authorConsent: true,
  ),
  // Prehab Guys, standing hamstring curl with a band.
  ExerciseType.hamstringCurl: ExerciseDemoLink(
    url: 'https://library.theprehabguys.com/vimeo-video/standing-hamstring-curl-band/',
    author: 'The Prehab Guys',
    authorConsent: true,
  ),
  // Physitrack, marching in place.
  ExerciseType.marching: ExerciseDemoLink(
    url: 'https://uk.physitrack.com/home-exercise-video/marching-in-place',
    author: 'Physitrack',
    authorConsent: true,
  ),
  // YouTube, "Balance exercise One leg stand" (hold a wall for support).
  ExerciseType.singleLegBalance: ExerciseDemoLink(
    url: 'https://www.youtube.com/watch?v=ZLxyh_PEstI',
    author: 'Rehab My Patient',
    authorConsent: true,
  ),
  // YouTube, "Wall Sit for Knee Pain". The presenter's credentials weren't confirmed.
  ExerciseType.wallSit: ExerciseDemoLink(
    url: 'https://www.youtube.com/watch?v=DlmFHesPvmw',
    author: 'NexStep PT',
    authorConsent: true,
  ),
  // Prehab Guys, assisted shoulder flexion with a dowel. Not an unassisted raise.
  ExerciseType.overheadRaise: ExerciseDemoLink(
    url: 'https://library.theprehabguys.com/vimeo-video/shoulder-flexion-aarom-dowel/',
    author: 'The Prehab Guys',
    authorConsent: true,
  ),
  // forwardPush (elbow push): no suitable video found, so it has no entry.
};
