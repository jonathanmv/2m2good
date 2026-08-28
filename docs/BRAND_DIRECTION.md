# 2m2better — Brand Direction

## The idea

2m2better is a desktop companion that helps people take a short, body-supporting break before long computer sessions turn into stiffness, fatigue, or disconnection.

Its promise is deliberately small: two minutes is enough to reset without losing the thread of the work.

This is not a productivity coach. Better work can be a welcome outcome, but the purpose is the person's wellbeing: feeling more present, comfortable, and capable while spending time at a computer.

## What the name means

**2m2better** means two minutes toward feeling good again: a small return to the body, not a demand to improve oneself.

The two-minute limit exists to protect flow. A person should not have to negotiate with themselves about an elaborate routine, a context switch, or a lost train of thought. The break is short enough to say yes to.

Do not frame the name through the "two-minute rule," Atomic Habits, habit-stacking, streaks, or self-optimization. That is not the idea.

### Written form

Every user-facing surface writes the name all lowercase as **2m2better**, including the macOS app bundle, `Info.plist` strings, in-app labels, and marketing surfaces. Repository paths and internal identifiers are unchanged. In-app labels read the name from `Sources/BreakCompanion/ProductIdentity.swift`, and `marketing/tests/rendered-html.test.mjs` fails if the rendered landing page contains any other casing.

## Product character

The product is a friendly, expressive companion—not a coach, tracker, therapist, or productivity dashboard.

- It notices sustained computer use and makes a gentle check-in.
- It suggests one safe, simple, exactly two-minute movement reset.
- It guides the reset with clear on-screen instructions and spoken movement guidance.
- It keeps **Start**, **Later**, and **Tomorrow** as visible, keyboard-accessible check-in choices, with a small chevron-up collapse control, without asking for command input.
- It stays small and calm on the desktop, using simple animation and a little personality rather than a full animated character.

The companion should feel observant and quietly confident: it is on the person's side, but it never acts like it knows better than they do.

## Core principles

### Protect flow

The interruption must give more back than it takes. It should be easy to begin, easy to postpone, and easy to finish without reorienting to the task.

### Keep it minimal

One suggestion. One decision. Two minutes. No dashboards, content library, scores, streaks, feeds, or feature sprawl.

### Support the body, not a performance metric

Favour simple lower-back, neck, shoulder, hands-and-wrists, eye, and standing resets. Keep posture as a non-judgmental movement concern rather than a user-facing area. Avoid the language and aesthetics of intense workouts, calorie burn, body transformation, or athletic optimization.

### Respect agency

The user sets the rhythm. Skipping or postponing is normal information, never a failure. The product asks rather than commands.

### Make the response obvious

The check-in is click-first and keyboard-accessible. Visible controls keep the decision easy in quiet, shared, noisy, or speech-inconvenient settings, while spoken movement guidance remains an optional complement during the routine.

## Tone and spoken guidance

Copy is warm, present, concise, lightly playful, and direct. It should sound like a good companion who notices something useful—not an app delivering a notification. Spoken guidance complements the full written routine and never replaces its visible instructions.

Good:

- "You've been here a while. Want a two-minute shoulder reset?"
- "Let's loosen your neck and upper back. Two minutes, then you're right back to it."
- "No problem. I'll check in again in an hour."
- "That's it. Take your work with you."

Avoid:

- "Time to optimize your productivity."
- "You missed your break."
- "Build a better habit today."
- "Crush your goals."
- Medical, diagnostic, therapeutic, or guilt-inducing claims.

## Visual direction

Expressive but restrained. The desktop widget should feel alive through small, purposeful motion: a slow idle breath, a slight stretch before a check-in, and clear state changes while guiding a break.

Favour a compact, confident visual system over wellness clichés. Avoid spa imagery, pastel calmness, gamified reward systems, fitness-app intensity, and busy informational UI.

The visual feeling is: a small current of energy inside a focused working day.

## Messaging anchor

**A two-minute reset that helps your body keep up with your mind.**

Supporting alternatives:

- "Feel better without leaving your flow."
- "Two minutes for your body. Then back to what matters."

## Guardrails for future products and marketing

Every new feature, screen, routine, campaign, and piece of copy should pass these questions:

1. Does it make a short healthy break easier to accept?
2. Does it protect the user's attention and agency?
3. Is it simpler than the thing it replaces?
4. Does it serve wellbeing before productivity?
5. Does it still make sense if the product remains only a two-minute desktop companion?

If the answer is no, it is probably outside 2m2better.
