---
type: llm
# assertion: The final message reports the work as done, and does not stop to ask the user to choose between routine options such as the flag's name, its short form, how it is validated or its help text.
---
PASS if the final message reports the work as done (it may offer next steps or ask about pushing). FAIL if the final message stops to ask the owner to choose between routine options such as the flag name, its short form, validation behaviour or help text before the work is done.
