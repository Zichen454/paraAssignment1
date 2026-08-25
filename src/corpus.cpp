#include "bpe.h"
#include <cstdint>
#include <cstring>
#include <fstream>
#include <stdexcept>
namespace bpe {
namespace {

inline bool is_separator(Byte b) {
    return b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D || b == 0x00;
}
//检查一批次8个bytes内有没有小于某个value的 内容，以此来快速判断分隔符的存在
inline std::uint64_t hasless_any(std::uint64_t word, unsigned limit) {
    const std::uint64_t ones = ~0ULL / 255;
    return (word - ones * limit) & ~word & (ones * 128);
}
}
std::vector<Byte> read_file(const std::string& path) {
    std::ifstream in(path, std::ios::binary | std::ios::ate);
    if (!in) {
        throw std::runtime_error("cannot open file: " + path);
    }
    const std::streamsize size = in.tellg();
    in.seekg(0, std::ios::beg);

    std::vector<Byte> data(static_cast<std::size_t>(size) + 1);
    if (size > 0) {
        in.read(reinterpret_cast<char*>(data.data()), size);
    }
    data.pop_back();
    return data;
}

//怎么正确的切开 原本可能很长的文本而不把单词分开也不花太长时间，
//在一个合适的长度比如input size/ p 的预估位置之后用8bit扫描和is seporator那个就 能找到合适的p
//但是输入太短的话这样会有概率直接超过下一个input/p的预估位置 直接把过短的输入取消并行执行
//又会用不了现成的测试
//以及合并的时候要保证 words的顺序还是正确的
//words 看起来不能共享，因为是在方法内部创建的所以 要么在外部创建shared的words ，要么还能怎么办呢
//方法内部不想修改了好麻烦
//inplace的问题主要是不能再原本的输入的调用第二次 但是只要每个线程想处理的部分是独立的就可以
// split_words: in place — whitespace becomes NUL, each Word is a C-string.
std::vector<Word> split_words(std::vector<Byte>& input) {
    input.push_back(Byte('\0'));//输入最后增加\0
    std::vector<Word> words;// 空words 最后装载每个指向单词开头的word
    words.reserve(input.size() / 3 + 1); //空间大小的预估
    Byte* p = input.data(); //input数字的第一个元素的地址
    const Byte* const end = input.data() + input.size();//指向数组最后一个元素还要后面的一位？
    while (p < end) { //所以只要数组还没用完就持续的进行循环 第一个小于最后一个
        while (p < end && is_separator(*p)) {
            ++p; //如果是separator ，就简单的+1来移动到下一个bit 直到真正的单词
        }
        if (p == end) {
            break; //没单词了就结束
        }
        words.push_back(Word{p}); //在跳出第一个while,p恰好指向一个单词的开头的时候
        //把这个单词的第一个字符的address 记录进words内
        //接下来，开始快速搜索这个单词的结尾在哪里

        while (p + 8 <= end) { //只要当前位置离end之间还有8 bytes 以上，就进行8 bytes的快速处理
            std::uint64_t chunk;
            std::memcpy(&chunk, p, 8); //把8 bytes的内容复制进chunk内？
            const std::uint64_t hits = hasless_any(chunk, 0x21);
            //因为separator 都小于这个所以用hasless 快速检索任何
            if (hits != 0) {
                p += __builtin_ctzll(hits) >> 3; //如果找到了，把p移动到第一个可能的分隔符address位置
                break;
            }
            p += 8;//没有找到分隔符，直接跳过
        }
        //这个快速检测循环找到疑似分隔符的东西并且完成了对p的合理的移动，然后

        while (p < end && !is_separator(*p)) {
            ++p;//只要不是真正的分隔符，就++来一位一位的找
        }
        *p = Byte('\0'); //找到了分隔符后把分隔符改成\0
        ++p; //再前进一位 开始准备找下一个单词
    }

    return words;
}

}
