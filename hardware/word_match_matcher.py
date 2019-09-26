
# Python model for word_match_matcher.vhd

import re

class Matcher:

    def __init__(self, search_data, whole_words=True, debug=False):
        super().__init__()

        assert len(search_data) >= 1 and len(search_data) <= 32
        self._search_data = '?' * (32 - len(search_data)) + search_data
        self._search_first = 32 - len(search_data)
        self._whole_words = whole_words

        self._first = True
        self._win_mat = [True] * 41

        self._debug = debug

    def check(self, string):
        if not string:
            self.feed('????????', 0, True)
            return
        amount = 0
        for i in range(0, len(string), 8):
            chars = string[i:i+8]
            count = len(chars)
            chars += '_' * (8 - count)
            last = i >= len(string) - 8
            amount += self.feed(chars, count, last)
        return amount

    def feed(self, chars, count, last):
        if self._debug:
            print(chars, count, last)

        chr_mat = [None] * 8
        for ii in range(8):
            word_bound = bool(re.match('[^a-zA-Z0-9_]', chars[ii])) or not self._whole_words
            chr_mat[ii] = [True] * 34
            chr_mat[ii][self._search_first] = word_bound
            for mi in range(self._search_first, 32):
                if ii >= count or chars[ii] != self._search_data[mi]:
                    chr_mat[ii][mi+1] = False
            if ii < count:
                chr_mat[ii][33] = word_bound

        if self._first:
            self._win_mat = [True] * 41
            for ci in range(41):
                if ci > self._search_first:
                    self._win_mat[ci] = False
            #for ci in range(0, self._search_first+1):
                #self._win_mat[ci] = True
        self._win_mat = [True] * 8 + self._win_mat[:-8]
        for ci in range(41):
            for ii in range(8):
                for mi in range(34):
                    if ci == mi + 7 - ii:
                        self._win_mat[ci] = self._win_mat[ci] and chr_mat[ii][mi]

        self._first = last

        win_amt = sum(self._win_mat[-8:])
        if last and self._win_mat[-9]:
            win_amt += 1

        if self._debug:
            print('   [%s]' % chars)
            for mi in range(34):
                if mi >= 1 and mi <= 32:
                    prefix = '[%s] ' % self._search_data[mi-1]
                else:
                    prefix = '~~~ '
                if mi == 0:
                    suffix = ''
                elif mi == 1:
                    suffix = '\\'
                else:
                    suffix = '\\' + str(int(self._win_mat[mi - 2]))
                print('%s%s%s' % (
                    prefix,
                    ''.join([str(int(chr_mat[ii][mi])) for ii in range(8)]),
                    suffix))
            print('     \\\\\\\\\\\\\\\\' + str(int(self._win_mat[34 - 2])))
            print('      %s = %d' % (
                ''.join([str(int(self._win_mat[-i-1])) for i in range(8)]),
                win_amt))
            print('   [%s]' % chars)

        return win_amt


def get_num_matches(pat, data):
    amount = 0
    for i in range(len(data) - len(pat) + 1):
        if data[i:i+len(pat)] == pat:
            amount += 1
    return amount

def check(pat, data, whole_words=True):
    actual = Matcher(pat, whole_words).check(data)

    if whole_words:
        # NOTE: this is only valid when the only word boundary is a space.
        expected = get_num_matches(' ' + pat + ' ', ' ' + data + ' ')
    else:
        expected = get_num_matches(pat, data)

    if actual != expected:
        Matcher(pat, whole_words, debug=True).check(data)
        print('boom: "%s" is in "%s" %dx for whole_word=%d, not %dx' % (
            pat, data, expected, whole_words, actual))
        assert False


check('test', 'test test 1 two three banana triangle', 0)
check(' test', 'test test 1 two three banana triangle', 0)
check(' test', ' test test 1 two three banana triangle', 0)
check('xtest', 'test test 1 two three banana triangle', 0)
check('test', 'test test 1 two three banana triangle', 1)
check(' test', 'test test 1 two three banana triangle', 1)
check(' test', ' test test 1 two three banana triangle', 1)
check('xtest', ' test test 1 two three banana triangle', 1)

check('triangle', 'test test 1 two three banana triangle', 0)
check('triangle ', 'test test 1 two three banana triangle', 0)
check('triangle ', 'test test 1 two three banana triangle ', 0)
check('trianglex', 'test test 1 two three banana triangle', 0)
check('triangle', 'test test 1 two three banana triangle', 1)
check('triangle ', 'test test 1 two three banana triangle', 1)
check('triangle ', 'test test 1 two three banana triangle ', 1)
check('trianglex', 'test test 1 two three banana triangle', 1)

check('a', 'test test 1 two three banana triangle', 0)
check('a', 'test test 1 two three banana triangle', 1)
check('test test 1 two three banana', 'test test 1 two three banana triangle', 1)

check('test', 'hello test there testest', 0)

check('here', 'And another line is herehereherehereherehere', 0)

#Matcher('a', whole_words=0).check('test test 1 two three banana triangle')
