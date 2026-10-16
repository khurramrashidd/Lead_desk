# Heuristic lint for the classes of issue `flutter analyze` keeps catching,
# so they are caught here instead of on the user's laptop.
import glob, re, sys, os

ROOT = sys.argv[1]
files = sorted(glob.glob(f'{ROOT}/lib/**/*.dart', recursive=True) + glob.glob(f'{ROOT}/test/*.dart'))

# Identifiers that mean a package import is really used.
PKG_SYMBOLS = {
    'cloud_firestore': ['FirebaseFirestore','DocumentSnapshot','QuerySnapshot','DocumentReference',
                        'CollectionReference','FieldValue','Timestamp','SetOptions','QueryDocumentSnapshot',
                        'FirebaseException','Query<','SnapshotOptions','AggregateQuery','GeoPoint','Blob',
                        'FieldPath','WriteBatch','Transaction','Source','GetOptions'],
    'firebase_auth': ['FirebaseAuth','User','UserCredential','GoogleAuthProvider','EmailAuthProvider',
                      'AuthCredential','FirebaseAuthException','OAuthProvider'],
    'cloud_functions': ['FirebaseFunctions','HttpsCallable','FirebaseFunctionsException','HttpsCallableResult'],
    'firebase_core': ['Firebase','FirebaseOptions','FirebaseApp'],
    'url_launcher': ['launchUrl','LaunchMode','canLaunchUrl'],
    'google_sign_in': ['GoogleSignIn','GoogleSignInAccount','GoogleSignInAuthentication'],
    'flutter/services.dart': ['Clipboard','ClipboardData','SystemChrome','SystemUiOverlayStyle','HapticFeedback',
                              'TextInputFormatter','FilteringTextInputFormatter','LengthLimitingTextInputFormatter',
                              'rootBundle','SystemSound','DeviceOrientation','MethodChannel','SystemNavigator'],
    'dart:convert': ['jsonEncode','jsonDecode','json.','base64','utf8','base64Encode','base64Decode','LineSplitter'],
    'dart:typed_data': ['Uint8List','ByteData','Float64List','Int32List'],
    'dart:math': ['math.','max(','min(','sqrt','pi','Random('],
    'dart:async': ['Timer','StreamController','Completer','StreamSubscription','scheduleMicrotask','unawaited'],
    'dart:io': ['File(','Directory(','Platform.','Process.','HttpClient'],
    'intl': ['DateFormat','NumberFormat','Intl.'],
    'record': ['AudioRecorder','RecordConfig','AudioEncoder','Amplitude'],
    'flutter/foundation.dart': ['kIsWeb','ValueNotifier','ChangeNotifier','debugPrint','kDebugMode',
                                'listEquals','mapEquals','describeEnum','compute(','defaultTargetPlatform',
                                'TargetPlatform','immutable','Key(','ValueListenable'],
}

bad = []
IMPORT = re.compile(r"^(?:import|export)\s+'([^']+)'(?:[^;]*)?;", re.M)

def strip_comments(src):
    src = re.sub(r'/\*.*?\*/', '', src, flags=re.S)
    return re.sub(r'//[^\n]*', '', src)

for f in files:
    src = open(f, encoding='utf-8').read()
    rel = os.path.relpath(f, ROOT)
    body_only = strip_comments(src)
    body = IMPORT.sub('', body_only)

    # 1) package / dart imports that nothing in the file uses
    for m in IMPORT.finditer(body_only):
        uri = m.group(1)
        key = None
        if uri.startswith('package:'):
            rest = uri[len('package:'):]
            pkg = rest.split('/')[0]
            if pkg == 'flutter':
                key = rest[len('flutter/'):]
                key = 'flutter/' + key
            else:
                key = pkg
        elif uri.startswith('dart:'):
            key = uri
        if key in PKG_SYMBOLS:
            if ' as ' in m.group(0):
                alias = m.group(0).split(' as ')[1].split(';')[0].strip()
                if re.search(rf'\b{re.escape(alias)}\.', body):
                    continue
                bad.append(f'{rel}: import {uri} as {alias} looks unused')
                continue
            if not any(sym in body for sym in PKG_SYMBOLS[key]):
                bad.append(f'{rel}: import {uri} looks unused')

    # 2) use_null_aware_elements
    for i, line in enumerate(body_only.splitlines(), 1):
        m = re.search(r'\bif\s*\(\s*(\w+)\s*!=\s*null\s*\)\s*\1!?\s*,', line)
        if m:
            bad.append(f'{rel}:{i}: use_null_aware_elements -> ?{m.group(1)},')
        m = re.search(r"\bif\s*\(\s*(\w+)\s*!=\s*null\s*\)\s*('[^']+'|\"[^\"]+\")\s*:\s*\1!?\s*,", line)
        if m:
            bad.append(f"{rel}:{i}: use_null_aware_elements -> {m.group(2)}: ?{m.group(1)},")

    # 3) literal \$ (escaped interpolation from heredoc generation)
    for i, line in enumerate(src.splitlines(), 1):
        if re.search(r'\\\$(\{|[A-Za-z_])', line):
            bad.append(fr'{rel}:{i}: literal \$ -- interpolation was escaped')

    # 4) const constructor wrapping a clearly non-const call
    for i, line in enumerate(body_only.splitlines(), 1):
        if re.search(r'\bconst\s+\w+\([^)]*\b(DateTime\.now|Theme\.of|MediaQuery\.of|context\.)', line):
            bad.append(f'{rel}:{i}: const wrapping a runtime value')

print(f'lint: {len(files)} dart files')
if bad:
    print('--- LINT ---')
    for b in bad: print(' ', b)
else:
    print('clean')
