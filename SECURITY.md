# Security Policy

## Supported versions

OpenSloper is in early development and has no stable release yet. Security fixes go into the `development` branch only. Once releases begin, this page will list which of them receive fixes.

## Reporting a vulnerability

Please do not report security problems in public issues, pull requests or discussions.

Report them privately through GitHub: on the repository's **Security** tab, choose **Report a vulnerability** ([direct link](https://github.com/billbsing/opensloper/security/advisories/new)). If you cannot use GitHub, email info@opensloper.com.

Include as much of this as you can:

- what the problem is and what an attacker could do with it;
- the app and version or commit (`opensloper-design`, `opensloper-measurements`, `opensloper-publish` or `opensloper-cli`), and your operating system;
- steps to reproduce it, and any file that triggers it (a pattern, measurement file or layout);
- a suggested fix, if you have one.

## What to expect

OpenSloper is maintained by one person in their spare time, so please allow some time for a reply. You should hear back within two weeks to confirm the report has been received. We will keep you informed while a fix is prepared, agree with you when the problem is made public, and credit you in the advisory unless you would rather not be named.

## Scope

Of most interest are problems that a crafted file or request could exploit, for example:

- loading pattern, measurement or layout files (crashes, memory corruption, reading or writing files outside what the user chose);
- the Automation API server started by `opensloper-cli serve`;
- the exporters (PDF, SVG, DXF, Blender) writing unexpected content or paths.

Problems in the bundled third-party packages (Clipper2, BGRABitmap, ConsoleTools) should also be reported to their own projects; tell us too if they affect OpenSloper.
