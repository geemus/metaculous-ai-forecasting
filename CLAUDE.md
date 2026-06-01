# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Install dependencies
bundle install

# Run a single forecast (post_id, forecaster_index 0-3)
ruby forecast.rb <post_id> [forecaster_index]

# Run end-to-end pipeline for a question
ruby ete.rb <post_id>

# Run research phase only
ruby tools_research.rb <post_id>

# Run news gathering only
ruby news.rb <post_id>

# Generate consensus from existing forecasts
ruby consensus.rb <post_id>

# Use test question IDs (defined in lib/utility.rb) to avoid skip logic
# Binary: 578, Numeric: 14333, Multiple Choice: 22427, Discrete: 38880
ruby forecast.rb 578 0
```

## Architecture

This is a multi-stage AI forecasting pipeline that submits probability forecasts to [Metaculus](https://metaculus.com) tournaments. It runs on GitHub Actions (triggered by `tournament.yml` every 20 minutes) and uses multiple LLM providers in parallel to generate diverse, calibrated forecasts.

### Pipeline Stages

```
news.rb → tools_research.rb → forecast.rb (×4 forecasters) → revise_forecast.rb (×4) → consensus.rb
```

1. **News** (`news.rb`) - Fetches and categorizes relevant news via AskNews API
2. **Research** (`tools_research.rb`) - Deep research using Claude Opus with web search tools
3. **Forecast** (`forecast.rb`) - 4 independent forecasters (Anthropic, OpenAI, Perplexity, DeepSeek)
4. **Revise** (`revise_forecast.rb`) - Each forecaster sees peers' estimates and revises
5. **Consensus** (`consensus.rb`) - Final consolidated forecast submitted to Metaculus

### Key Files

- **`lib/provider.rb`** - Multi-provider LLM factory. `Provider::FORECASTERS = [:anthropic, :openai, :perplexity, :deepseek]`. Both `:anthropic` and `:openai` route through OpenRouter; `:perplexity` and `:deepseek` use their own clients.
- **`lib/metaculus.rb`** - Metaculus API client. `Question` class wraps question data; handles all 4 question types (binary, numeric, discrete, multiple_choice).
- **`lib/prompts.rb`** - System prompts and ERB templates. `SUPERFORECASTER_SYSTEM_PROMPT` encodes the Bayesian methodology (base rates, explicit adjustments, uncertainty calibration).
- **`lib/response.rb`** - Parses LLM responses across providers. Extracts XML-tagged forecast values (`<probability>`, `<percentiles>`, `<probabilities>`).
- **`lib/tools.rb`** - Defines `SEARCH_TOOL` (calls Perplexity sonar-pro for web search) and `Tools.dispatch` (centralized tool-call router used by OpenRouter, DeepSeek, and Perplexity).
- **`lib/utility.rb`** - File-based caching in `tmp/{post_id}/`. All prompts and outputs are cached for auditability.

### Question Types & Output Formats

| Type | Format | Example |
|------|--------|---------|
| Binary | `<probability>X%</probability>` | Yes/No questions |
| Numeric | `<percentiles>` with 11 values (5,10,20,...,95) | Continuous range |
| Discrete | Same as numeric (mapped to named categories) | Named buckets |
| Multiple Choice | `<probabilities>` summing to 100% | Named options |

### Caching

All intermediate data is cached in `tmp/{post_id}/`:
- `post.json` - Question data
- `research.json` - Research output
- `news.json` - News items
- `inputs/` - Prompts sent to LLMs
- `outputs/` - Raw LLM responses
- `forecasts/` - Parsed forecast JSON
- `consensus/` - Final consensus data

### Required Environment Variables

```
ANTHROPIC_API_KEY
DEEPSEEK_API_KEY
OPEN_ROUTER_API_KEY
PERPLEXITY_API_KEY
ASKNEWS_API_KEY
METACULUS_BOT_API_TOKEN
METACULUS_BOT_ID
```
