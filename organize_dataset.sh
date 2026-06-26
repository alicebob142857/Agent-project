#!/usr/bin/env bash
set -euo pipefail

# 请在 /root/data 目录下运行
# 当前目录应当包含 example-s5、example-s5-0624、example-s5-2 等文件夹

echo "Current directory: $(pwd)"
echo "Start organizing dataset..."

# 1. 删除所有 zip 文件
echo "Deleting zip files..."
find . -type f -name "*.zip" -print -delete

# 2. 创建统一的数据目录
mkdir -p dataset/docs
mkdir -p dataset/single_turn
mkdir -p dataset/multi_turn
mkdir -p dataset/multimodal/images

# 3. 定义安全移动函数
move_if_exists() {
    src="$1"
    dst="$2"

    if [ -e "$src" ]; then
        echo "Moving: $src -> $dst"
        mv -v "$src" "$dst"
    else
        echo "Skip, not found: $src"
    fi
}

# 4. 整理 example-s5 中的数据
move_if_exists "./example-s5/example-s5/instructions.docx" \
               "./dataset/docs/instructions.docx"

move_if_exists "./example-s5/example-s5/examples/question.json" \
               "./dataset/single_turn/question.json"

move_if_exists "./example-s5/example-s5/examples/answer.jsonl" \
               "./dataset/single_turn/answer.jsonl"

# 5. 整理 example-s5-0624 中的多轮文本数据
move_if_exists "./example-s5-0624/example-s5-0624/多轮输入输出样例-0624.json" \
               "./dataset/multi_turn/questions_0624.json"

move_if_exists "./example-s5-0624/example-s5-0624/多轮输入输出样例答案-0624.jsonl" \
               "./dataset/multi_turn/answers_0624.jsonl"

# 6. 整理 example-s5-2 中的多模态多轮数据
move_if_exists "./example-s5-2/example-s5-补充/样例数据-图片-多轮.json" \
               "./dataset/multimodal/questions_with_images.json"

move_if_exists "./example-s5-2/example-s5-补充/样例数据答案.jsonl" \
               "./dataset/multimodal/answers.jsonl"

move_if_exists "./example-s5-2/example-s5-补充/T1.jpg" \
               "./dataset/multimodal/images/T1.jpg"

move_if_exists "./example-s5-2/example-s5-补充/T2.jpg" \
               "./dataset/multimodal/images/T2.jpg"

# 7. 清理已经空掉的 example 目录
echo "Removing empty example directories..."
find ./example-s5 ./example-s5-0624 ./example-s5-2 -type d -empty -print -delete 2>/dev/null || true

echo
echo "Done. Final dataset structure:"
tree dataset