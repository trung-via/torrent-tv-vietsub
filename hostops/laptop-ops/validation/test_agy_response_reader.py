import json
import unittest
from agy_response_reader import extract


def pack(*events):
    return '\n'.join(json.dumps(e) for e in events)


class ReaderTests(unittest.TestCase):
    def test_final(self):
        r = extract(pack({'event':'result','result':{'response':'Recipe V5'}}))
        self.assertEqual(r['final_responses'], ['Recipe V5'])
        self.assertEqual(r['status'], 'FINAL_PRESENT')

    def test_empty(self):
        r = extract(pack({'event':'result','result':{'response':''}}))
        self.assertEqual(r['status'], 'NO_FINAL_TEXT')

    def test_partial(self):
        r = extract(pack({'event':'message','role':'assistant','content':'Partial report'}, {'event':'result','result':{'response':''}}))
        self.assertEqual(r['status'], 'PARTIAL_TEXT_ONLY')
        self.assertEqual(r['assistant_fragments'][0]['text'], 'Partial report')

    def test_delta(self):
        r = extract(pack({'event':'content_block_delta','delta':{'type':'text_delta','text':'A'}}))
        self.assertEqual(r['assistant_fragments'][0]['text'], 'A')

    def test_no_reasoning_or_user_echo(self):
        r = extract(pack({'event':'message','role':'user','content':'EXAMPLE_SECRET_PAYLOAD'}, {'event':'message','role':'assistant','content':[{'type':'thinking','text':'EXAMPLE_SECRET_PAYLOAD'},{'type':'text','text':'Public'}]}, {'event':'content_block_delta','delta':{'type':'thinking_delta','text':'EXAMPLE_SECRET_PAYLOAD'}}))
        self.assertNotIn('EXAMPLE_SECRET_PAYLOAD', json.dumps(r))
        self.assertEqual(len(r['assistant_fragments']),1)

    def test_tool(self):
        r = extract(pack({'step_update':{'tool_name':'call_mcp_tool','tool_info':{'parameters':{'ToolName':'evaluate_script'},'output':'EXAMPLE_SECRET_PAYLOAD'}}}))
        self.assertEqual(r['tool_outcomes'][0]['tool'],'evaluate_script')
        self.assertNotIn('EXAMPLE_SECRET_PAYLOAD', json.dumps(r))

    def test_denied(self):
        r = extract(pack({'step_update':{'tool_name':'other','tool_info':{'error':'permission denied'}}}, {'event':'result','result':{'response':''}}), 'permission denied')
        self.assertEqual(r['errors'][0]['error'],'permission denied')
        self.assertEqual(r['status'],'NO_FINAL_TEXT')

    def test_usage(self):
        r = extract(pack({'event':'result','result':{'usage':{'total_tokens':7}}}))
        self.assertEqual(r['usage'][0]['usage']['total_tokens'],7)

    def test_unknown_and_invalid(self):
        r = extract('bad\n'+pack({'event':'new_event','custom':'EXAMPLE_SECRET_PAYLOAD'}))
        self.assertEqual(r['invalid_lines'],[1])
        self.assertIn('custom', r['event_schema_inventory'][0]['keys'])
        self.assertNotIn('EXAMPLE_SECRET_PAYLOAD', json.dumps(r))


if __name__ == '__main__':
    unittest.main()
