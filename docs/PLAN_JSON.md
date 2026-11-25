# 训练计划 JSON 格式

设置 → 计划 JSON 导入与导出。支持选择JSON文件或直接粘贴完整文本。导出为 UTF-8 JSON，版本 `1`。计划及动作的数组顺序决定排序，不导出训练记录或健康数据。

```json
{
  "version": 1,
  "plans": [
    {
      "id": "E4E5F4F7-A9F1-4DA4-814D-D1719DF8408D",
      "name": "胸部训练",
      "exercises": [
        {
          "id": "4D6BDD2C-0A24-4107-84BE-AB3B5F70B01F",
          "name": "卧推",
          "sets": 4,
          "restSeconds": 90,
          "restAfterLastSet": false,
          "restOverrides": {"3": 120}
        }
      ]
    }
  ]
}
```

计划、动作名称去除空白后不能为空，最长100字符；组数1–100，默认和覆盖休息秒数1–86400，覆盖组号须在1至组数范围内。ID须为有效UUID，同一文件计划ID不重复，同一计划动作ID不重复。休息覆盖字段可省略，兼容旧版动作数据。末组覆盖不会隐式启用末组休息。

单次导入最多10MB，不设置计划或每计划动作数量上限。文件先整体解码和校验，确认后追加；生成新的计划和动作ID，避免覆盖或修改现有内容。保存失败回滚，不部分导入。重复导入将得到副本，不做隐式合并。

## 替代动作

完整可导入示例：[chest-with-alternatives.json](../examples/chest-with-alternatives.json)。打开文件复制全部文本，在App设置的“粘贴JSON文本”中粘贴，然后“校验并追加导入”；也可下载保存为`.json`后选择文件导入。

每个动作可增加可选的 `alternatives` 数组，每项包含 `id`、`name`、`restSeconds` 和可省略的 `restOverrides`。替代项共用所在位置的 `sets` 和 `restAfterLastSet`，不另加动作位置/总组数，默认休息和按组覆盖分别独立。该位置的主动作及替代项ID不能重复，非法替代项会使整个文件拒绝导入。

训练的待训练状态可切换到替代项或原动作；休息/暂停时须先结束或跳过休息。完成组数不清零，历史逐组保留实际使用的动作名称；训练中的选择不修改源计划。新计划导入、复制会为主动作和替代项生成新ID。旧JSON无alternatives时按无替代项处理。

## version 2：计划 → 训练日 → 动作

version1的plans继续按训练日解读。version2增加顶层programs（id/name），每个plans条目可用programID归属上层计划。所有引用须有效，导入后上层/训练日/动作/替代项ID重新映射。通用导入保留新版分组；从具体计划详情导入则明确归入该计划。

用户五分化文件的分组版本：[five-day-split.json](../examples/five-day-split.json)，保持原5个训练日、26动作和88组及替代配置。已导入的旧训练应通过“整理已有训练”归组，避免重新导入产生副本。
