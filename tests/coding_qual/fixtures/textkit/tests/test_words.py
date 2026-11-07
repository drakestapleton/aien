import unittest

from textkit import words


class WordsTest(unittest.TestCase):
    def test_count_words(self):
        self.assertEqual(words.count_words("a b  c"), 3)
        self.assertEqual(words.count_words(""), 0)

    def test_title_case(self):
        self.assertEqual(words.title_case("hELLO   wORLD"), "Hello World")

    def test_truncate_words(self):
        self.assertEqual(words.truncate_words("one two three four", 2), "one two")
        self.assertEqual(words.truncate_words("one two", 5), "one two")

    def test_type_error(self):
        with self.assertRaises(TypeError):
            words.count_words(3)


if __name__ == "__main__":
    unittest.main()
