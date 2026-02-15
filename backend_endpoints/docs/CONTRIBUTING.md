# Contributing to Guardian AI

Thank you for your interest in contributing to Guardian AI. This document outlines the expectations and workflow for contributing code, documentation, and ideas.

## Ways to Contribute

- Report bugs and request features
- Improve documentation and examples
- Implement new features or enhancements
- Add tests and improve reliability
- Review pull requests

## Before You Start

- Check existing issues and discussions to avoid duplicates.
- For larger changes, open an issue or discussion first to align on scope and approach.
- Keep security and child privacy in mind when designing features.

## Development Setup

1. Create and activate a Python virtual environment.
2. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```
3. Apply migrations:
   ```bash
   python manage.py migrate
   ```
4. Run the server:
   ```bash
   python manage.py runserver
   ```

For full setup details, see [user_guide.md](user_guide.md).

## Branching and Workflow

- Fork the repository and create a feature branch:
  ```bash
  git checkout -b feature/short-description
  ```
- Keep changes focused and small where possible.
- Write clear, descriptive commit messages.

## Code Standards

- Follow existing project patterns and structure.
- Keep APIs consistent and backwards-compatible when possible.
- Avoid reformatting unrelated code.
- Add or update docstrings where behavior changes.

## Testing

- Add tests for new behavior where feasible.
- Run relevant tests before submitting a PR:
  ```bash
  python manage.py test
  ```

Here's how to get started:

1. **Fork** the repository
2. **Create a feature branch** (`git checkout -b feature/your-feature`)
3. **Make your changes**
4. **Write tests** for new features
5. **Submit a pull request** with a clear description of your changes

### Areas for Contribution

- **Backend Enhancements**: Optimize data ingestion, improve API performance, add new monitoring features
- **Frontend Improvements**: Enhance dashboard UI/UX, add new visualizations, improve accessibility
- **Mobile Development**: Expand Android client capabilities, add iOS support, improve battery efficiency
- **Content Safety**: Implement advanced content filtering, ML-based risk detection, malware scanning
- **Testing & QA**: Write unit tests, integration tests, and end-to-end tests
- **Documentation**: Improve setup guides, API documentation, and developer resources

## 🐛 Reporting Issues

Found a bug or have a feature request? Please open an issue on our [GitHub Issues](https://github.com/seraphguardlabs/GuardianAI-backend/issues) page with:

- Clear title and description
- Steps to reproduce (for bugs)
- Expected vs. actual behavior
- Environment details (OS, Python version, etc.)


## Pull Request Guidelines

- Provide a clear summary of what the PR changes.
- Link related issues or discussions.
- Include screenshots or sample output for UI changes.
- Note any migrations or configuration changes.

## Security and Privacy

If you discover a security or privacy issue, do **not** open a public issue. Instead, contact the maintainers via the project contact listed in the README.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
