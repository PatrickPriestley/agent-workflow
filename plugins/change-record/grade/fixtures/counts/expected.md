# Change skill report

No score rows here: run `transcripts grade` for the steps. The counts and the coverage below need only the transcripts and the index entries.

## Counts

What each session took, read from the transcripts in this folder and not from a grader: 3 of 3 sessions have a transcript here. Output tokens are counted once per message, and "-" means the transcript carries no token usage. Minutes run from a session's first line to its last, waiting included. A turn from a person is a message a person typed after the first one; whether it was a correction is not judged. No threshold is applied: the middle is the median, and the least and the most name their session.

### change-record:change, blob unknown

| Count | Sessions | Middle | Least | Most |
|---|---|---|---|---|
| Output tokens | 2 | 312.5 | 125 (d2000000) | 500 (d1000000) |
| Tool calls | 3 | 2 | 1 (d3000000) | 3 (d1000000) |
| Calls that failed or were refused | 3 | 0 | 0 (d2000000) | 2 (d1000000) |
| Messages written | 3 | 1 | 1 (d2000000) | 3 (d1000000) |
| Characters written | 3 | 21 | 20 (d2000000) | 62 (d1000000) |
| Characters in the last message | 3 | 21 | 20 (d2000000) | 21 (d1000000) |
| Turns from a person after the first | 3 | 0 | 0 (d2000000) | 1 (d1000000) |
| Minutes, first line to last | 3 | 1.5 | 0.3 (d3000000) | 10 (d1000000) |

| Session | Output tokens | Tool calls | Failed or refused | Messages | Characters | Last message | Turns from a person | Minutes |
|---|---|---|---|---|---|---|---|---|
| d1000000 | 500 | 3 | 2 | 3 | 62 | 21 | 1 | 10 |
| d2000000 | 125 | 2 | 0 | 1 | 20 | 20 | 0 | 1.5 |
| d3000000 | - | 1 | 0 | 1 | 21 | 21 | 0 | 0.3 |

## Skill coverage

Of 3 sessions here, 2 used a skill and 1 used none. A session used a skill when its index entry lists it, or its transcript shows the skill called or its file read, by the rule the capture tool applies today.

| Skill | Sessions |
|---|---|
| change-record:change | 2 |
| none | 1 |
