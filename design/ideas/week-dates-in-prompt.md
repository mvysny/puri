# The week's dates in the system prompt

The system prompt gives only today's date (`AgentSession#system_prompt`), and small models slip
on the sums: asked "What's on Thursday?", Qwen 3.5 4B, Bolt E4B and gpt-oss named the wrong date,
and a Qwen run with thinking took Saturday for 27 November (`R_model_eval`). Ornith didn't slip.

Proposal: spell out the next seven days, a line each with its weekday, the way the weather tool
lists its days so "this weekend" is a line to read (`D_weather`). Our own prompt's change
(`D_own_prompts`).

- `Q_measure`: rerun the date tasks on Qwen, thinking, before and after: `thursday`,
  `saturday-evening`, `friday-followup`, `interview-lea`, `sauna-weather`
  (`rake eval CONFIGS='Qwen3.5-4B, thinking' TASKS=…`).
