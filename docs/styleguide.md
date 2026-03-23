## Styleguide

### Issues/commits

We will use the following conventions:

- Issues use future imperative tense (e.g. `"Add triangle clipping"`, not `"Added triangle clipping"`). Titles are kept short and descriptive, with further details in the issue body.
- Commit messages follow the same imperative style, but also be prefixed with a conventional commit tag to categorize the change. Tags include:
  - `feat:` new feature
  - `fix:` bug fix 
  - `refactor:` code restructuring with no behavior change
  - `chore:` maintenance tasks, config, dependencies
  - `docs:` documentation updates
  - `test:` adding or updating tests

### Pull Requests & Branches
Pull requests should be tied to issues. So say we have an issue `#1 "Implement SDL3 window rendering"`, the corresponding branch is created as:

```
git switch -c issue/1-implement-sdl3-window-rendering
```

PR titles should mirror the associated issue. **PRs require at least one approving review before merge**, and we should squash-merge when possible to keep the main branch history clean.

### Code Style
We follow the [Zig standard library style](https://ziglang.org/documentation/master/#Style-Guide) for all source code. That is:
- TitleCase for types (structs, enums, unions, errors)
- camelCase for regular functions
- snake_case for variables, constants, file names, and pretty much everything else
