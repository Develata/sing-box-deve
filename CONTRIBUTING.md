# Contributing

Thanks for your interest in contributing to `sing-box-deve`.

## Development Notes

- Keep shell scripts POSIX-friendly where practical, and run `bash -n` checks before submitting.
- Preserve security-first defaults (no firewall disable/flush behavior).
- Keep interactive UX clear: explain each choice and allow Enter for default values.

## Pull Request Checklist

- Update docs when behavior changes (`README.md`, `docs/V1-SPEC.md`).
- Add or update examples in `examples/` when introducing new config options.
- Ensure syntax validation passes:

```bash
bash -n sing-box-deve.sh lib/*.sh
```

## Reporting Issues

- Include OS version, provider mode, command used, and full error output.
- If reporting protocol issues, include the enabled protocol list and relevant redacted settings.
