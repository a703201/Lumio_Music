/*
 * Copyright (c) 2024 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { Animator, AnimatorResult } from '@kit.ArkUI';
import { Logger } from '../utils/Logger';
import { LrcEntry } from './LrcEntry';
import { angleToRadian } from './LrcUtils';
import { Rectangle, LyricTopPosition, LyricScrollEffect } from './LyricConst';

const TAG: string = 'LrcView';

/**
 * Default number of rows.
 */
const NONE_LINE: number = -1;

/**
 * Stars a few corners
 */
const STAR_ANGLE_NUMBER: number = 5;

/**
 * No lyrics.
 */
const EMPTY_LYRIC: LrcEntry = {
  lineStartTime: 0,
  lineDuration: 0,
  lineWords: '此歌曲为纯音乐，请您欣赏',
  words: []
};

/**
 * Lyrics gradient color spacing.
 */
const GRADIENT_PROGRESS_SPACE = 0.0000001;

/**
 * Lyrics gradient color spacing.
 */
const GRADIENT_PROGRESS_MAX = 1 - GRADIENT_PROGRESS_SPACE;

@Component
export default struct shiLrcView {
  /**
   * Current lyric time [ms].
   */
  @Prop @Watch('onTimeUpdated') lyricMilliSecondsTime: number;
  /**
   * Lyrics content.
   */
  @Prop @Watch('onLyricUpdated') mLrcEntryList: Array<LrcEntry> = [];
  /**
   * Lyrics scrolling effect.
   */
  @Prop @Watch('onTimeUpdated') lyricScrollEffect: LyricScrollEffect = LyricScrollEffect.Line;
  @Prop @Watch('playLyrics') isPlay: boolean = false;
  @Prop @Watch('onTranslationToggled') showTranslation: boolean = true;
  @Prop @Watch('onBgChanged') backgroundIsDark: boolean = true;
  private mNormalTextColor = '#99ffffff';
  private viewWidth: number = 360;
  private viewHeight: number = 500;
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private mCurrentLine: number = NONE_LINE;
  private readonly TEXT_ADD_SIZE = 2;
  lyricRectangle: Rectangle = new Rectangle(0, 0, 0, 0);
  /**
   * Location of the lyrics.
   */
  readonly lyricTopPosition: LyricTopPosition = LyricTopPosition.Top;
  /**
   * Initial position of the first line of the lyrics.
   */
  private initFirstLineY: number = 0;
  private animator: AnimatorResult = this.getUIContext().createAnimator({
    duration: 400,
    easing: 'linear',
    delay: 0,
    fill: 'forwards',
    direction: 'normal',
    iterations: 1,
    begin: 0,
    end: 1
  });
  /**
   * Text size of the lyrics, in vp.
   */
  private mNormalTextSize: number = 20;
  /**
   * Spacing of each line of lyrics, in vp. This spacing plays the star animation or white dot disappearing effect.
   */
  private mDividerHeight = 24;
  /**
   * 原文与翻译之间的额外间距（vp）。
   */
  private mTranslateGap: number = 14;
  /**
   * Size of the current lyrics, in vp.
   */
  private mCurrentTextSize: number = 24;
  /**
   * Lyrics font.
   */
  private fontFamily = 'HarmonyHeiTi';
  /**
   * The text color of the currently displayed lyrics
   */
  private mCurrentTextColor = '#FFFFFF';
  /**
   * Lyrics font weight.
   */
  private fontWeight = 'bold';
  /**
   * 翻译文字字号（小于正文）。
   */
  private mTranslateTextSize: number = 15;
  /**
   * 翻译文字颜色：非当前行（暗）/ 当前行（亮）。
   */
  private mTranslateColorNormal: string = '#80ffffff';
  private mTranslateColorCurrent: string = '#d6ffffff';
  /**
   * Distance between the lyrics and the left border.
   */
  private paddingLeft = 0;
  /**
   * Distance between the lyrics and the right border.
   */
  private paddingRight = 0;
  /**
   * Distance between the lyrics and the top border.
   */
  private paddingTop = 0;
  /**
   * Distance between lyrics and bottom border.
   */
  private paddingBottom = 0;
  /**
   * The width of the lyrics.
   */
  private lrcWidth: number = 0;
  /**
   * Height lyrics.
   */
  private lrcHeight: number = 0;
  /**
   * X-axis position of each line of text.
   */
  private lrcX: number = 0;
  /**
   * Y-axis position of each line of text.
   */
  private lrcY: number = 0;
  /**
   * Records the current canvas offset.
   */
  private curCanvasOffsetY: number = 0;
  /**
   * How many degrees is each angle of a star.
   */
  private starAverageAngle: number = 0;
  /**
   * The outer angle of the stars.
   */
  private starOutCircleAngle: number = 0;
  /**
   * The interior angles of the stars.
   */
  private starInCircleAngle: number = 0;
  /**
   * The path of the stars.
   */
  private starsPath2D: Path2D = new Path2D();
  /**
   * Star Color
   */
  private starsColor: string = '#18BBFC';

  startAnimator(desOffsetY: number) {
    if (this.animator) {
      this.animator.finish();
    }

    this.animator = this.getUIContext().createAnimator({
      duration: 400,
      easing: 'linear',
      delay: 0,
      fill: 'forwards',
      direction: 'normal',
      iterations: 1,
      begin: this.curCanvasOffsetY,
      end: -desOffsetY
    });
    let that = this;
    Logger.info('[startAnimator] curOffset:' + this.curCanvasOffsetY + ',desOffset:' + (-desOffsetY));
    this.animator.onFrame = (value) => {
      that.drawContent(value);
    };
    this.animator.onCancel = () => {
    };
    this.animator.onFinish = () => {
    };
    this.animator.play();
  }

  playLyrics() {
    if (this.isPlay) {
      this.animator.play();
    } else {
      this.animator.pause();
    }
  }

  /**
   * Draw a star.
   *
   * @param x
   * @param y
   * @param outRadius
   * @param inRadius
   * @param rotateAngle
   */
  private drawStars(x: number, y: number, outRadius: number, inRadius: number, rotateAngle: number) {
    this.starsPath2D = new Path2D();
    this.context.fillStyle = this.starsColor;
    for (let i = 0; i < STAR_ANGLE_NUMBER; i++) {
      let outX = (
        Math.cos(angleToRadian(rotateAngle + this.starOutCircleAngle + i * this.starAverageAngle)) * outRadius) + x;
      let outY = -(
        Math.sin(angleToRadian(rotateAngle + this.starOutCircleAngle + i * this.starAverageAngle)) * outRadius) + y;
      let inX = (
        Math.cos(angleToRadian(rotateAngle + this.starInCircleAngle + i * this.starAverageAngle)) * inRadius) + x;
      let inY = -(
        Math.sin(angleToRadian(rotateAngle + this.starInCircleAngle + i * this.starAverageAngle)) * inRadius) + y;
      if (i === 0) {
        this.starsPath2D.moveTo(outX, outY);
      }
      this.starsPath2D.lineTo(outX, outY);
      this.starsPath2D.lineTo(inX, inY);
    }
    this.starsPath2D.closePath();
    this.context.fill(this.starsPath2D);
  }

  private calculate() {
    this.lrcWidth = this.viewWidth - this.paddingLeft - this.paddingRight;
    this.lrcHeight = this.viewHeight - this.paddingTop - this.paddingBottom;
    if (this.initFirstLineY === 0) {
      switch (this.lyricTopPosition) {
        case LyricTopPosition.Middle:
          this.initFirstLineY = this.paddingTop + this.lrcHeight / 2.8;
          break;
        case LyricTopPosition.Top:
          this.initFirstLineY = this.paddingTop;
          break;
        default:
          break;
      }
    }
    this.lrcX = 0;
    this.lrcY = this.initFirstLineY;

    this.starAverageAngle = 360 / STAR_ANGLE_NUMBER;
    this.starOutCircleAngle = 90 - this.starAverageAngle;
    let halfAverageAngle = this.starAverageAngle / 2;
    this.starInCircleAngle = halfAverageAngle + this.starOutCircleAngle;
  }

  private reset() {
    this.lrcY = this.initFirstLineY;
  }

  drawMiddle() {
    this.context.translate(0, -this.curCanvasOffsetY);
    this.context.beginPath();
    this.context.strokeStyle = Color.Red;
    this.context.moveTo(0, this.viewHeight / 2);
    this.context.lineTo(this.viewWidth, this.viewHeight / 2);
    this.context.stroke();
    this.context.closePath();
    this.context.translate(0, this.curCanvasOffsetY);
  }

  private getLineHeight(text: string, isCurrent?: boolean, translation?: string): number {
    let lineHeight = 0;
    if (isCurrent) {
      this.context.font = this.fontWeight + ' ' + this.mCurrentTextSize + 'vp ' + this.fontFamily;
    } else {
      this.context.font = this.fontWeight + ' ' + this.mNormalTextSize + 'vp ' + this.fontFamily;
    }
    let textMetrics: TextMetrics = this.context.measureText(text);
    if (textMetrics.width > this.lrcWidth) {
      let start = 0;
      let end = text.length - 1;
      let textTemp = text;
      while (this.context.measureText(text.substring(start, end)).width > this.lrcWidth) {
        if (textTemp.lastIndexOf(' ') !== -1) {
          end = textTemp.lastIndexOf(' ');
          textTemp = textTemp.substring(0, end);
        } else {
          end--;
        }
      }
      if (this.context.measureText(text.substring(start, end)).width <= this.lrcWidth) {
        lineHeight += textMetrics.height;
        start = end;
      }
      if (start < text.length - 1) {
        lineHeight += textMetrics.height;
      }
    } else {
      lineHeight = textMetrics.height;
    }
    if (this.showTranslation && translation && translation.length > 0) {
      this.context.font = this.fontWeight + ' ' + this.mTranslateTextSize + 'vp ' + this.fontFamily;
      let tMetrics = this.context.measureText(translation);
      lineHeight += this.mDividerHeight * 0.5 + this.mTranslateGap + tMetrics.height;
    }
    return lineHeight;
  }

  /**
   * Back to Gradient.
   * @param startX
   * @param startY
   * @param endX
   * @param endY
   * @param progress
   * @returns
   */
  private progressGrad(startX: number, startY: number, endX: number, endY: number, progress: number) {
    let grad = this.context.createLinearGradient(startX, startY, endX, endY);
    grad.addColorStop(progress, this.mCurrentTextColor);
    grad.addColorStop(progress + GRADIENT_PROGRESS_SPACE, this.mNormalTextColor);
    return grad;
  }

  private drawMultipleLine(lyric: LrcEntry, textMetrics: TextMetrics, isCurrent: boolean): number {
    let lineHeight = 0;
    let start = 0;
    let end = 1;
    this.context.textAlign = 'start';
    let text = lyric.lineWords;
    let textTemp = lyric.lineWords;
    end = text.length - 1;

    while (this.context.measureText(text.substring(start, end)).width > this.lrcWidth) {
      if (textTemp.lastIndexOf(' ') !== -1) {
        end = textTemp.lastIndexOf(' ');
        textTemp = textTemp.substring(0, end);
      } else {
        end--;
      }
    }

    if (this.context.measureText(text.substring(start, end)).width <= this.lrcWidth) {
      if (start === 0) {
        this.lrcY = this.lrcY + textMetrics.height + this.mDividerHeight;
      } else {
        this.lrcY = this.lrcY + textMetrics.height;
      }
      lineHeight += textMetrics.height;

      if (isCurrent) {
        this.context.fillText(text.substring(start, end), this.lrcX, this.lrcY, this.lrcWidth);
      } else {
        this.context.fillText(text.substring(start, end), this.lrcX, this.lrcY, this.lrcWidth);
      }
      start = end;
    }

    if (start !== 0 && text.charAt(start) === ' ') {
      start += 1;
    }

    if (start < text.length - 1) {
      this.lrcY = this.lrcY + textMetrics.height;
      lineHeight += textMetrics.height;
      if (isCurrent) {
        this.context.fillText(text.substring(start), this.lrcX, this.lrcY, this.lrcWidth);
      } else {
        this.context.fillText(text.substring(start), this.lrcX, this.lrcY, this.lrcWidth);
      }
    }
    return lineHeight;
  }

  private drawSingleLine(lyric: LrcEntry, textMetrics: TextMetrics, isCurrent: boolean): number {
    this.lrcY = this.lrcY + this.mDividerHeight + textMetrics.height;
    let text = lyric.lineWords;
    if (isCurrent) {
      switch (this.lyricScrollEffect) {
        case LyricScrollEffect.LetterScaleGradient:
          if (lyric.words && lyric.words.length > 0) {
            let startX = this.lrcX - textMetrics.width / 2;
            let endX = startX + textMetrics.width;
            let gradY = this.lrcY - textMetrics.height / 2;

            let wordX = startX;
            this.context.textAlign = 'start';
            for (let i = 0; i < lyric.words.length; i++) {
              let wordStartTime = lyric.lineStartTime + lyric.words[i].wordStartTime;
              let wordEndTime = lyric.lineStartTime + lyric.words[i].wordStartTime + lyric.words[i].duration;
              if (wordStartTime <= this.lyricMilliSecondsTime && wordEndTime >= this.lyricMilliSecondsTime) {
                let wordProgress =
                  (this.lyricMilliSecondsTime - wordStartTime) / lyric.words[i].duration / lyric.words.length;
                let wordPassedProgress = i / lyric.words.length;
                let progress = wordPassedProgress + wordProgress;
                this.context.fillStyle = this.progressGrad(startX, gradY, endX, gradY, progress);
                this.context.font =
                  this.fontWeight + ' ' + (this.mCurrentTextSize + this.TEXT_ADD_SIZE) + 'vp ' + this.fontFamily;
                this.context.fillText(lyric.words[i].text, wordX, this.lrcY + this.TEXT_ADD_SIZE / 2, this.lrcWidth);
              } else {
                this.context.font = this.fontWeight + ' ' + this.mCurrentTextSize + 'vp ' + this.fontFamily;
                this.context.fillText(lyric.words[i].text, wordX, this.lrcY, this.lrcWidth);
              }
              wordX += this.context.measureText(lyric.words[i].text).width;
            }
          } else {
            this.context.textAlign = 'center';
            this.context.fillText(text, this.lrcX, this.lrcY, this.lrcWidth);
          }
          break;
        case LyricScrollEffect.LetterGradient:
          if (lyric.words && lyric.words.length > 0) {
            this.context.textAlign = 'center';
            let startX_g = this.lrcX - textMetrics.width / 2;
            let endX_g = startX_g + textMetrics.width;
            let gradY_g = this.lrcY - textMetrics.height / 2;

            let progress = 0;
            let findPlayingWord = false;
            if (lyric.words && lyric.words.length > 0) {
              for (let i = 0; i < lyric.words.length; i++) {
                let wordStartTime = lyric.lineStartTime + lyric.words[i].wordStartTime;
                let wordEndTime = lyric.lineStartTime + lyric.words[i].wordStartTime + lyric.words[i].duration;
                if (wordStartTime <= this.lyricMilliSecondsTime && wordEndTime >= this.lyricMilliSecondsTime) {
                  let wordProgress =
                    (this.lyricMilliSecondsTime - wordStartTime) / lyric.words[i].duration / lyric.words.length;
                  let wordPassedProgress = i / lyric.words.length;
                  progress = wordPassedProgress + wordProgress;
                  findPlayingWord = true;
                  break;
                }
              }
            }
            if (!findPlayingWord) {
              if (this.lyricMilliSecondsTime < lyric.lineStartTime) {
                progress = 0;
              } else if (this.lyricMilliSecondsTime >= lyric.lineStartTime + lyric.lineDuration) {
                progress = GRADIENT_PROGRESS_MAX;
              } else {
                Logger.error('This should not be happening.');
              }
            }

            this.context.fillStyle = this.progressGrad(startX_g, gradY_g, endX_g, gradY_g, progress);
            this.context.fillText(text, this.lrcX, this.lrcY, this.lrcWidth);
          } else {
            this.context.textAlign = 'center';
            this.context.fillText(text, this.lrcX, this.lrcY, this.lrcWidth);
          }
          break;
        case LyricScrollEffect.LetterStar:
          if (lyric.words && lyric.words.length > 0) {
            let textStartX = this.lrcX - textMetrics.width / 2;
            let textEndX = textStartX + textMetrics.width;
            let gradY_Star = this.lrcY - textMetrics.height / 2;

            let wordXX = textStartX;
            let starX = textStartX;
            let starRotate = 0;
            this.context.textAlign = 'start';
            let findPlayingWordStar = false;
            if (lyric.words && lyric.words.length > 0) {
              for (let i = 0; i < lyric.words.length; i++) {
                let wordStartTime = lyric.lineStartTime + lyric.words[i].wordStartTime;
                let wordEndTime = lyric.lineStartTime + lyric.words[i].wordStartTime + lyric.words[i].duration;
                if (wordStartTime <= this.lyricMilliSecondsTime && wordEndTime >= this.lyricMilliSecondsTime) {
                  let wordProgress =
                    (this.lyricMilliSecondsTime - wordStartTime) / lyric.words[i].duration / lyric.words.length;
                  let wordPassedProgress = i / lyric.words.length;
                  let progress = wordPassedProgress + wordProgress;
                  this.context.fillStyle = this.progressGrad(textStartX, gradY_Star, textEndX, gradY_Star, progress);
                  this.context.font = this.fontWeight + ' ' + this.mCurrentTextSize + 'vp ' + this.fontFamily;
                  this.context.fillText(lyric.words[i].text, wordXX, this.lrcY, this.lrcWidth);
                  findPlayingWordStar = true;
                  starX = wordXX + this.context.measureText(lyric.words[i].text).width / 2;
                } else {
                  this.context.font = this.fontWeight + ' ' + this.mCurrentTextSize + 'vp ' + this.fontFamily;
                  this.context.fillText(lyric.words[i].text, wordXX, this.lrcY, this.lrcWidth);
                }
                wordXX += this.context.measureText(lyric.words[i].text).width;
              }
            }

            if (!findPlayingWordStar) {
              if (this.lyricMilliSecondsTime < lyric.lineStartTime) {
                starX = textStartX;
              } else if (this.lyricMilliSecondsTime > lyric.lineStartTime + lyric.lineDuration) {
                starX = this.lrcX + textMetrics.width / 2 -
                  this.context.measureText(lyric.words[lyric.words.length-1].text).width / 2;
              } else {
                Logger.error('This should not be happening.');
              }
              let starY = this.lrcY - textMetrics.height;
              this.drawStars(starX, starY, this.mDividerHeight / 2, this.mDividerHeight / 4, 0);
            } else {
              let starY = this.lrcY - textMetrics.height;
              this.drawStars(starX, starY, this.mDividerHeight / 2, this.mDividerHeight / 4, starRotate);
            }
          } else {
            this.context.textAlign = 'center';
            this.context.fillText(text, this.lrcX, this.lrcY, this.lrcWidth);
          }
          break;
        default:
          this.context.textAlign = 'start';
          this.context.fillText(text, this.lrcX, this.lrcY, this.lrcWidth);
          break;
      }
    } else {
      this.context.textAlign = 'start';
      this.context.fillText(text, this.lrcX, this.lrcY, this.lrcWidth);
    }
    return textMetrics.height;
  }

  /**
   * Draws each line of lyrics and returns the height of each line.
   * @param lyric
   * @param isCurrent
   * @returns
   */
  private drawLyricLine(lyric: LrcEntry, isCurrent: boolean): number {
    let lineHeight = 0;
    if (isCurrent) {
      this.context.font = this.fontWeight + ' ' + this.mCurrentTextSize + 'vp ' + this.fontFamily;
      this.context.fillStyle = this.mCurrentTextColor;
    } else {
      this.context.font = this.fontWeight + ' ' + this.mNormalTextSize + 'vp ' + this.fontFamily;
      this.context.fillStyle = this.mNormalTextColor;
    }
    this.context.textBaseline = 'bottom';
    let textMetrics: TextMetrics = this.context.measureText(lyric.lineWords);

    if (textMetrics.width > this.lrcWidth) {
      lineHeight = this.drawMultipleLine(lyric, textMetrics, isCurrent);
    } else {
      lineHeight = this.drawSingleLine(lyric, textMetrics, isCurrent);
    }

    // 翻译：字号更小、颜色更暗，绘制在正文下方以区分原文
    if (this.showTranslation && lyric.translation && lyric.translation.length > 0) {
      this.context.font = this.fontWeight + ' ' + this.mTranslateTextSize + 'vp ' + this.fontFamily;
      this.context.fillStyle = isCurrent ? this.mTranslateColorCurrent : this.mTranslateColorNormal;
      this.context.textBaseline = 'bottom';
      this.context.textAlign = 'start';
      let tMetrics = this.context.measureText(lyric.translation);
      this.lrcY = this.lrcY + this.mDividerHeight * 0.5 + this.mTranslateGap;
      this.drawWrappedTranslation(lyric.translation);
      lineHeight += this.mDividerHeight * 0.5 + this.mTranslateGap + tMetrics.height;
    }
    return lineHeight;
  }

  /**
   * 绘制翻译文本，超出宽度时按空格/字符折行。
   */
  private drawWrappedTranslation(text: string): void {
    this.context.font = this.fontWeight + ' ' + this.mTranslateTextSize + 'vp ' + this.fontFamily;
    let remaining = text;
    let guard = 0;
    while (remaining.length > 0 && guard < 8) {
      guard++;
      let whole = this.context.measureText(remaining);
      if (whole.width <= this.lrcWidth) {
        this.context.fillText(remaining, this.lrcX, this.lrcY, this.lrcWidth);
        this.lrcY = this.lrcY + whole.height;
        break;
      }
      let piece = remaining;
      let pieceMetrics = this.context.measureText(piece);
      while (pieceMetrics.width > this.lrcWidth && piece.length > 1) {
        let sp = piece.lastIndexOf(' ');
        if (sp <= 0) {
          piece = piece.substring(0, piece.length - 1);
        } else {
          piece = piece.substring(0, sp);
        }
        pieceMetrics = this.context.measureText(piece);
      }
      this.context.fillText(piece, this.lrcX, this.lrcY, this.lrcWidth);
      this.lrcY = this.lrcY + whole.height;
      remaining = remaining.substring(piece.length).replace(/^\s+/, '');
      if (piece.length === 0) {
        break;
      }
    }
  }

  /**
   * Offset position of the target object.
   *
   * @param desOffsetY
   */
  private drawContent(desOffsetY: number, change?: boolean) {
    Logger.info(TAG, JSON.stringify(change))
    this.context.clearRect(0, 0, this.viewWidth, this.lrcY + this.viewHeight);
    this.reset();

    this.context.globalCompositeOperation = 'source-over';
    this.lrcY = this.initFirstLineY + desOffsetY;
    this.curCanvasOffsetY = desOffsetY;

    if (this.mLrcEntryList && this.mLrcEntryList.length > 0) {
      let index = 0;
      for (let mLrcEntryListElement of this.mLrcEntryList) {
        let isCurrentLine = this.mCurrentLine === index ? true : false;
        this.drawLyricLine(mLrcEntryListElement, isCurrentLine);
        index++;
      }
    } else {
      this.drawLyricLine(EMPTY_LYRIC, true);
    }

    this.updateLyricArea(this.paddingLeft, this.paddingTop, this.viewWidth - this.paddingRight,
      this.viewHeight - this.paddingBottom);

    if (this.mLrcEntryList && this.mLrcEntryList.length > 0) {
      this.context.globalCompositeOperation = 'source-in';
      let grad = this.context.createLinearGradient(0, 0, 0, this.viewHeight);
      grad.addColorStop(0.0, '#00ffffff');
      grad.addColorStop(0.15, '#ffffffff');
      grad.addColorStop(0.3, '#ffffffff');
      grad.addColorStop(0.7, '#4dffffff');
      grad.addColorStop(1.0, '#00ffffff');
      this.context.fillStyle = grad;
      this.context.fillRect(0, 0, this.viewWidth, this.viewHeight);
    }
  }

  /**
   * Area where the lyrics are updated.
   * @param left
   * @param top
   * @param right
   * @param bottom
   */
  private updateLyricArea(left: number, top: number, right: number, bottom: number) {
    this.lyricRectangle = new Rectangle(left, top, right, bottom);
  }

  hasLrc(): boolean {
    return this.mLrcEntryList && this.mLrcEntryList.length > 0;
  }

  /**
   * How far to offset to a particular line.
   * @param line
   * @returns
   */
  getOffset(line: number): number {
    let offsetY = 0;
    switch (this.lyricTopPosition) {
      case LyricTopPosition.Top:
        for (let i = 0; i <= line && i < this.mLrcEntryList.length; i++) {
          const tr = this.showTranslation ? this.mLrcEntryList[i].translation : '';
          if (i === line) {
            offsetY += this.getLineHeight(this.mLrcEntryList[i].lineWords, true, tr) / 2
              - this.getLineHeight(this.mLrcEntryList[i].lineWords, false, tr) / 2;
          } else {
            offsetY += this.getLineHeight(this.mLrcEntryList[i].lineWords, false, tr)
              + this.mDividerHeight;
          }
        }
        break;
      case LyricTopPosition.Middle:
        for (let i = 0; i <= line && i < this.mLrcEntryList.length; i++) {
          const tr = this.showTranslation ? this.mLrcEntryList[i].translation : '';
          if (i === line) {
            offsetY += this.getLineHeight(this.mLrcEntryList[i].lineWords, true, tr) / 2
              + this.mDividerHeight;
          } else {
            offsetY += this.getLineHeight(this.mLrcEntryList[i].lineWords, false, tr)
              + this.mDividerHeight;
          }
        }
        break;
      default:
        break;
    }
    return offsetY;
  }

  /**
   * Animated scroll to specified position.
   * @param line
   */
  smoothScrollTo(line: number) {
    let offset = this.getOffset(line);
    Logger.info('[smoothScrollTo] line:' + line + ',offset:' + offset);
    this.startAnimator(offset);
  }

  /**
   * The lyrics have changed.
   */
  onLyricUpdated() {
    this.mCurrentLine = NONE_LINE;
    this.onTimeUpdated();
  }

  /**
   * The lyric time is updated. The lyrics need to be scrolled to the specified position.
   */
  onTimeUpdated() {
    if (!this.hasLrc()) {
      this.drawContent(0);
      return;
    }
    let line = this.findShowLine(this.lyricMilliSecondsTime);
    if (line !== this.mCurrentLine) {
      this.mCurrentLine = line;
      this.smoothScrollTo(line);
    } else {
      this.drawContent(this.curCanvasOffsetY);
    }
  }

  /**
   * Return the row corresponding to the current time.
   * @param milliSeconds
   * @returns
   */
  findShowLine(milliSeconds: number): number {
    if (this.mLrcEntryList && this.mLrcEntryList.length > 0) {
      for (let index = 0; index < this.mLrcEntryList.length; index++) {
        if (this.mLrcEntryList[index].lineStartTime <= milliSeconds
          && this.mLrcEntryList[index].lineStartTime + this.mLrcEntryList[index].lineDuration >= milliSeconds) {
          return index;
        }
      }
    }
    return this.mCurrentLine;
  }

  /**
   * 根据背景明暗切换歌词配色方案。
   */
  private applyColorScheme(): void {
    if (this.backgroundIsDark) {
      // 深色背景：浅色文字（默认方案）
      this.mNormalTextColor = '#99ffffff';
      this.mCurrentTextColor = '#FFFFFF';
      this.mTranslateColorNormal = '#80ffffff';
      this.mTranslateColorCurrent = '#d6ffffff';
    } else {
      // 浅色背景：深色文字
      this.mNormalTextColor = '#99000000';
      this.mCurrentTextColor = '#000000';
      this.mTranslateColorNormal = '#66000000';
      this.mTranslateColorCurrent = '#99000000';
    }
  }

  /**
   * 背景明暗变化后，重新应用配色并重绘。
   */
  onBgChanged() {
    this.applyColorScheme();
    this.drawContent(this.curCanvasOffsetY);
  }

  /**
   * 翻译开关变化后重绘。
   */
  onTranslationToggled() {
    this.drawContent(this.curCanvasOffsetY);
  }

  aboutToAppear() {
    this.applyColorScheme();
  }

  build() {
    Canvas(this.context)
      .onAreaChange((oldArea: Area, newArea: Area) => {
        this.viewWidth = Number.parseFloat(newArea.width.toLocaleString());
        this.viewHeight = Number.parseFloat(newArea.height.toLocaleString());
        if (oldArea.width.toLocaleString() !== newArea.width.toLocaleString()) {
          this.calculate();
          let line = this.findShowLine(this.lyricMilliSecondsTime);
          let offset = this.getOffset(line);
          this.drawContent(offset);
        }
        if (oldArea.height.toLocaleString() !== newArea.height.toLocaleString()) {
          this.calculate();
          let line = this.findShowLine(this.lyricMilliSecondsTime);
          let offset = this.getOffset(line);
          this.drawContent(-offset, true);
        }
      })
  }
}