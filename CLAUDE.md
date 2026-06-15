{\rtf1\ansi\ansicpg1252\cocoartf2870
\cocoatextscaling0\cocoaplatform0{\fonttbl\f0\fnil\fcharset0 Menlo-Regular;\f1\fnil\fcharset0 Menlo-Bold;\f2\fnil\fcharset0 Menlo-Italic;
}
{\colortbl;\red255\green255\blue255;\red129\green95\blue3;\red255\green255\blue255;\red0\green0\blue0;
\red0\green0\blue0;}
{\*\expandedcolortbl;;\csgenericrgb\c50580\c37140\c1210;\csgenericrgb\c100000\c100000\c100000;\csgenericrgb\c0\c0\c0\c85000;
\csgenericrgb\c0\c0\c0\c70000;}
\paperw11900\paperh16840\margl1440\margr1440\vieww11520\viewh8400\viewkind0
\deftab593
\pard\tx593\pardeftab593\pardirnatural\partightenfactor0

\f0\fs36 \cf2 \cb3 #\cf4  CLAUDE.md
\fs24 \
\
Guidance for Claude (or Claude Code) when working in this repository.\
\

\fs30 \cf2 ##\cf4  Project Overview
\fs24 \
\
\cf2 **
\f1\b \cf4 Reactor Core Balancing
\f0\b0 \cf2 **\cf4  is a small SwiftUI prototype game inspired by the\
AZ-5 / control rod scenes in HBO's \cf2 *
\f2\i \cf4 Chernobyl
\f0\i0 \cf2 *\cf4 . The player manages a 5x5 grid\
of control rods that automatically "retract" over time, increasing overall\
core reactivity. Tapping a rod re-inserts it. If average reactivity hits\
100%, the core melts down.\
\
This is currently a \cf2 **
\f1\b \cf4 single-file prototype
\f0\b0 \cf2 **\cf4  (\cf2 `\cf5 ReactorCoreGame.swift\cf2 `\cf4 ) meant\
to be dropped into a fresh Xcode SwiftUI project. There is no Xcode project\
file checked in yet \'97 just the SwiftUI source.\
\

\fs30 \cf2 ##\cf4  Tech Stack
\fs24 \
\
\cf2 - \cf4 Swift + SwiftUI only (no SpriteKit, no UIKit, no third-party dependencies)\
\cf2 - \cf4 Target platforms: iOS / iPadOS / macOS (anything that supports SwiftUI's\
  \cf2 `\cf5 LazyVGrid\cf2 `\cf4 , \cf2 `\cf5 @StateObject\cf2 `\cf4 , and \cf2 `\cf5 ObservableObject\cf2 `\cf4 )\
\cf2 - \cf4 No external package manager dependencies (no SPM packages required)\
\

\fs30 \cf2 ##\cf4  File Structure
\fs24 \
\
\cf2 - `\cf5 ReactorCoreGame.swift\cf2 `\cf4  \'97 contains everything:\
  \cf2 - `\cf5 ControlRod\cf2 `\cf4  \'97 model struct representing a single rod's insertion value\
    (0.0 = fully inserted/safe/green, 1.0 = fully withdrawn/danger/red)\
  \cf2 - `\cf5 ReactorViewModel\cf2 `\cf4  \'97 \cf2 `\cf5 ObservableObject\cf2 `\cf4  driving the simulation loop via\
    \cf2 `\cf5 Timer\cf2 `\cf4 , computing reactivity, and handling meltdown state\
  \cf2 - `\cf5 ReactorCoreView\cf2 `\cf4  \'97 main SwiftUI view (header, reactivity meter, 5x5 grid)\
  \cf2 - `\cf5 RodCell\cf2 `\cf4  \'97 individual tappable rod cell\
  \cf2 - \cf4 Preview provider + commented \cf2 `\cf5 @main\cf2 `\cf4  App struct example for standalone use\
\

\fs30 \cf2 ##\cf4  Core Simulation Logic
\fs24 \
\
All gameplay tuning lives in \cf2 `\cf5 ReactorViewModel\cf2 `\cf4  as private constants:\
\
\cf2 - `\cf5 driftPerTick\cf2 `\cf4  (default \cf2 `\cf5 0.012\cf2 `\cf4 ) \'97 how fast rods drift toward "withdrawn"\
  each tick, randomized per-rod by a \cf2 `\cf5 0.6...1.4\cf2 `\cf4  multiplier\
\cf2 - `\cf5 tapReduction\cf2 `\cf4  (default \cf2 `\cf5 0.30\cf2 `\cf4 ) \'97 how much a single tap re-inserts a rod\
\cf2 - `\cf5 tickInterval\cf2 `\cf4  (default \cf2 `\cf5 0.2\cf2 `\cf4 s) \'97 simulation tick rate\
\
\cf2 `\cf5 reactivity\cf2 `\cf4  is the simple average of all 25 rods' \cf2 `\cf5 insertion\cf2 `\cf4  values.\
Meltdown triggers at \cf2 `\cf5 reactivity >= 1.0\cf2 `\cf4 , stopping the timer and showing the\
overlay with a reset button.\
\
When adjusting difficulty, prefer changing these constants over restructuring\
the tick/update flow \'97 the loop is intentionally simple (tick \uc0\u8594  drift all\
rods \uc0\u8594  recompute reactivity \u8594  check meltdown).\
\

\fs30 \cf2 ##\cf4  Conventions & Style
\fs24 \
\
\cf2 - \cf4 Keep this as \cf2 **
\f1\b \cf4 pure SwiftUI
\f0\b0 \cf2 **\cf4  \'97 do not introduce SpriteKit, Combine\
  publishers beyond \cf2 `\cf5 @Published\cf2 `\cf4 /\cf2 `\cf5 ObservableObject\cf2 `\cf4 , or external state\
  management libraries unless explicitly requested.\
\cf2 - \cf4 Keep the simulation deterministic-ish and readable: avoid hidden global\
  state, keep tuning constants named and grouped together.\
\cf2 - \cf4 Color logic (\cf2 `\cf5 ControlRod.color\cf2 `\cf4 , \cf2 `\cf5 meterColor\cf2 `\cf4 ) interpolates green \uc0\u8594  yellow\
  \uc0\u8594  red. If adding new visual states, follow the same RGB-interpolation\
  pattern rather than introducing asset-based colors, to keep this a\
  zero-asset, single-file prototype.\
\cf2 - \cf4 Animations use \cf2 `\cf5 .easeOut\cf2 `\cf4  with short durations (0.15\'960.2s) \'97 keep new\
  animations snappy and consistent with this.\
\

\fs30 \cf2 ##\cf4  Things to Watch For
\fs24 \
\
\cf2 - `\cf5 Timer.scheduledTimer\cf2 `\cf4  is used directly; if this grows beyond a prototype,\
  consider switching to a \cf2 `\cf5 TimelineView\cf2 `\cf4  or \cf2 `\cf5 Combine\cf2 `\cf4 -based clock for better\
  SwiftUI lifecycle handling (e.g. pausing when the app backgrounds).\
\cf2 - \cf4 There's currently no persistence, settings screen, sound, or haptics \'97\
  these are natural next features but aren't implemented.\
\cf2 - \cf4 No automated tests yet. If adding logic-heavy features (e.g. scoring,\
  difficulty curves), consider extracting \cf2 `\cf5 ReactorViewModel\cf2 `\cf4 's pure\
  calculations into testable helper functions.\
\

\fs30 \cf2 ##\cf4  Possible Next Features (not yet implemented)
\fs24 \
\
\cf2 - \cf4 An AZ-5-style "SCRAM" button: instantly drives all rods toward 0, but with\
  a brief delay/lockout or even a short reactivity \cf2 *
\f2\i \cf4 spike
\f0\i0 \cf2 *\cf4  first (a nod to\
  the real AZ-5 positive scram effect)\
\cf2 - \cf4 Difficulty curve: increase \cf2 `\cf5 driftPerTick\cf2 `\cf4  over time as \cf2 `\cf5 elapsedSeconds\cf2 `\cf4 \
  grows\
\cf2 - \cf4 Sound/haptic feedback on tap and on meltdown\
\cf2 - \cf4 High score / best survival time tracking\
\cf2 - \cf4 Xcode project files (\cf2 `\cf5 .xcodeproj\cf2 `\cf4  / Swift Package) so the game can be\
  opened and run directly instead of being pasted into a new project\
}